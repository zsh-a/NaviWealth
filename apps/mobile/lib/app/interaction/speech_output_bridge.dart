import 'dart:async';
import 'dart:collection';

import '../../core/ai/session/delivery_ledger.dart';
import '../../core/ai/session/interaction_ids.dart';
import '../../core/speech/speech_output.dart';
import 'interaction_session_coordinator.dart';

/// Serializes semantic output segments through one SpeechOutput session.
///
/// The bridge owns playback timing only. AgentEventAdapter supplies generated
/// segments, while the Coordinator remains the only owner of epoch changes,
/// delivery ledger updates, and interruption policy.
final class SerializedSpeechOutputBridge {
  SerializedSpeechOutputBridge({
    required SpeechOutput speechOutput,
    required InteractionSessionCoordinator coordinator,
  }) : _speechOutput = speechOutput,
       _coordinator = coordinator;

  final SpeechOutput _speechOutput;
  final InteractionSessionCoordinator _coordinator;
  final Queue<_QueuedSpeechSegment> _queue = Queue<_QueuedSpeechSegment>();
  final Set<int> _finishedEpochs = <int>{};

  Future<void>? _pumpFuture;
  SpeechOutputSession? _activeSession;
  _QueuedSpeechSegment? _activeEntry;
  Completer<void>? _activeCompletion;
  bool _paused = false;
  bool _closed = false;
  int _generation = 0;

  /// Enqueues a segment using the Coordinator's current session/turn/epoch.
  ///
  /// A segment without an active turn is ignored because it has no safe
  /// semantic owner. This also keeps provider output from becoming an
  /// orphaned response after a session has been closed.
  void enqueue(OutputSegment segment) {
    if (_closed) return;
    final state = _coordinator.state;
    final turnId = state.activeTurnId;
    if (turnId == null) return;
    _queue.add(
      _QueuedSpeechSegment(
        segment: segment,
        stamp: InteractionStamp(
          sessionId: state.sessionId,
          turnId: turnId,
          epoch: state.responseEpoch,
          sequence: state.sequence,
        ),
      ),
    );
    _ensurePump();
  }

  /// Marks the Agent response complete. The bridge stops the output lane only
  /// after all segments for that epoch have been delivered.
  Future<void> finish(ResponseEpoch epoch, {required bool interrupted}) async {
    if (_closed || _coordinator.state.responseEpoch != epoch) return;
    if (interrupted) {
      _discardEpoch(epoch);
      final active = _activeSession;
      final activeEntry = _activeEntry;
      if (active != null && activeEntry?.stamp.epoch == epoch) {
        await _cancelActive(active);
      }
      if (!_closed && _coordinator.state.responseEpoch == epoch) {
        _coordinator.outputPlaybackStopped(interrupted: true);
      }
      return;
    }
    _finishedEpochs.add(epoch.value);
    _tryFinishOutput(epoch);
  }

  /// Pauses the current native utterance and prevents the next queued segment
  /// from starting. This is called for BargeInCandidate, before a semantic
  /// interruption is committed.
  Future<void> pause() async {
    if (_closed) return;
    _paused = true;
    final active = _activeSession;
    if (active != null) await active.pause();
  }

  /// Resumes a false interruption or restarts the queue after a candidate was
  /// resolved without creating a new response epoch.
  Future<void> resume() async {
    if (_closed) return;
    _paused = false;
    final active = _activeSession;
    if (active != null) {
      await active.resume();
    }
    _ensurePump();
  }

  /// Invalidates and cancels all output belonging to a stale response epoch.
  /// This never attempts to roll back a domain side effect; it only stops
  /// presentation work that no longer owns the session.
  Future<void> interrupt({required ResponseEpoch staleEpoch}) async {
    if (_closed) return;
    _generation++;
    // A committed barge-in follows a candidate pause. The new epoch owns a
    // fresh output queue, so it must be allowed to pump immediately.
    _paused = false;
    _discardEpoch(staleEpoch);
    final active = _activeSession;
    final activeEntry = _activeEntry;
    if (active != null && activeEntry?.stamp.epoch == staleEpoch) {
      await _cancelActive(active);
    }
    _ensurePump();
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _paused = false;
    _generation++;
    _queue.clear();
    _finishedEpochs.clear();
    final active = _activeSession;
    if (active != null) await _cancelActive(active);
    final pump = _pumpFuture;
    if (pump != null) await pump;
  }

  void _ensurePump() {
    if (_closed || _paused || _pumpFuture != null) return;
    final pump = _pumpQueue();
    _pumpFuture = pump;
    unawaited(
      pump.then<void>((_) {
        _finishPump(pump);
      }),
    );
  }

  void _finishPump(Future<void> pump) {
    if (!identical(_pumpFuture, pump)) return;
    _pumpFuture = null;
    if (!_closed && !_paused && _queue.isNotEmpty) _ensurePump();
  }

  Future<void> _pumpQueue() async {
    while (!_closed && !_paused) {
      final entry = _takeNextLiveEntry();
      if (entry == null) return;
      final generation = _generation;
      _activeEntry = entry;
      SpeechOutputSession session;
      try {
        session = await _speechOutput.speak(
          SpeechOutputRequest(stamp: entry.stamp, segment: entry.segment),
        );
      } on Object {
        _activeEntry = null;
        // A provider failure must not block later interaction turns. The
        // current epoch is discarded by the host on the next turn; no text
        // is marked delivered here because playback never started.
        _tryFinishOutput(entry.stamp.epoch);
        continue;
      }

      if (!_isLive(entry, generation)) {
        _activeEntry = null;
        await session.cancel();
        continue;
      }

      _activeSession = session;
      final interrupted = await _consume(session);
      _activeEntry = null;
      _activeSession = null;

      if (interrupted) {
        _discardEpoch(entry.stamp.epoch);
        continue;
      }
      _tryFinishOutput(entry.stamp.epoch);
    }
  }

  Future<bool> _consume(SpeechOutputSession session) async {
    final done = Completer<void>();
    _activeCompletion = done;
    var interrupted = false;
    late final StreamSubscription<SpeechOutputEvent> subscription;
    subscription = session.events.listen(
      (event) {
        if (event is SpeechOutputStopped) {
          interrupted = event.interrupted;
          if (!_closed && event.interrupted) {
            _coordinator.acceptSpeechOutputEvent(event);
          }
          if (!done.isCompleted) done.complete();
          return;
        }
        if (!_closed) _coordinator.acceptSpeechOutputEvent(event);
      },
      onError: (Object _, StackTrace _) {
        if (!done.isCompleted) done.complete();
      },
      onDone: () {
        if (!done.isCompleted) done.complete();
      },
      cancelOnError: false,
    );
    try {
      await done.future;
    } finally {
      await subscription.cancel();
      if (identical(_activeCompletion, done)) _activeCompletion = null;
    }
    return interrupted;
  }

  Future<void> _cancelActive(SpeechOutputSession active) async {
    final completion = _activeCompletion;
    try {
      await active.cancel();
    } finally {
      if (completion != null && !completion.isCompleted) completion.complete();
    }
  }

  _QueuedSpeechSegment? _takeNextLiveEntry() {
    while (_queue.isNotEmpty) {
      final entry = _queue.removeFirst();
      if (_isLive(entry, _generation)) return entry;
    }
    return null;
  }

  bool _isLive(_QueuedSpeechSegment entry, int generation) =>
      !_closed &&
      generation == _generation &&
      _coordinator.state.sessionId == entry.stamp.sessionId &&
      _coordinator.state.responseEpoch == entry.stamp.epoch;

  void _discardEpoch(ResponseEpoch epoch) {
    _queue.removeWhere((entry) => entry.stamp.epoch.value <= epoch.value);
    _finishedEpochs.remove(epoch.value);
  }

  void _tryFinishOutput(ResponseEpoch epoch) {
    if (_closed || !_finishedEpochs.contains(epoch.value)) return;
    if (_activeEntry != null ||
        _queue.any((entry) => entry.stamp.epoch == epoch)) {
      return;
    }
    if (_coordinator.state.responseEpoch != epoch) return;
    _finishedEpochs.remove(epoch.value);
    _coordinator.outputPlaybackStopped(interrupted: false);
  }
}

final class _QueuedSpeechSegment {
  const _QueuedSpeechSegment({required this.segment, required this.stamp});

  final OutputSegment segment;
  final InteractionStamp stamp;
}
