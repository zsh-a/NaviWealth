import 'dart:async';

import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

import '../../core/ai/contracts/interaction.dart';
import '../../core/ai/intent/ai_intent_invocation.dart';
import '../../core/ai/session/delivery_ledger.dart';
import '../../core/ai/session/interaction_events.dart';
import '../../core/ai/session/interaction_ids.dart';
import '../../core/ai/session/interaction_reducer.dart';
import '../../core/ai/session/interaction_state.dart';
import '../../core/ai/session/interruption_policy.dart';
import '../../core/speech/speech_input.dart';
import '../../core/speech/speech_output.dart';
import 'voice_interaction_adapter.dart';

final class InteractionTurnRequest {
  const InteractionTurnRequest({
    required this.sessionId,
    required this.turnId,
    required this.epoch,
    required this.text,
    required this.origin,
    this.cancelToken,
    this.systemContext,
    this.model,
    this.interactionResponse,
    this.resumeTurnId,
  });

  final SessionId sessionId;
  final TurnId turnId;
  final ResponseEpoch epoch;
  final String text;
  final InteractionInputOrigin origin;
  final CancelToken? cancelToken;
  final String? systemContext;
  final String? model;
  final AiInteractionResponse? interactionResponse;
  final String? resumeTurnId;
}

typedef InteractionTurnHandler =
    Future<void> Function(InteractionTurnRequest request);

/// Thin host-side coordinator around the pure InteractionSession reducer.
///
/// It owns event sequencing, speech-session wiring, and cancellation hooks;
/// the Agent Runtime remains responsible for semantic execution and domain
/// gateways remain responsible for truth and side effects.
class InteractionSessionCoordinator {
  InteractionSessionCoordinator({
    required SessionId sessionId,
    AiIntentInvocation? invocation,
    SpeechInput? speechInput,
    InteractionTurnHandler? onTurnCommitted,
    void Function()? onBargeInCandidate,
    void Function()? onFalseInterruption,
    void Function(ResponseEpoch staleEpoch)? onEpochAdvanced,
    void Function()? onSpeechEnded,
    void Function(Object error, StackTrace stackTrace)? onTurnError,
    VoiceInteractionResponseDecoder? responseDecoder,
    BargeInPolicy bargeInPolicy = const BargeInPolicy(),
    Uuid? uuid,
    DateTime Function()? clock,
  }) : _state = InteractionState.initial(
         sessionId: sessionId,
         invocation: invocation,
       ),
       _speechInput = speechInput,
       _onTurnCommitted = onTurnCommitted,
       _onBargeInCandidate = onBargeInCandidate,
       _onFalseInterruption = onFalseInterruption,
       _onEpochAdvanced = onEpochAdvanced,
       _onSpeechEnded = onSpeechEnded,
       _onTurnError = onTurnError,
       _responseDecoder = responseDecoder ?? decodeVoiceInteractionResponse,
       _bargeInPolicy = bargeInPolicy,
       _uuid = uuid ?? const Uuid(),
       _clock = clock ?? DateTime.now;

  final SpeechInput? _speechInput;
  final InteractionTurnHandler? _onTurnCommitted;
  final void Function()? _onBargeInCandidate;
  final void Function()? _onFalseInterruption;
  final void Function(ResponseEpoch staleEpoch)? _onEpochAdvanced;
  final void Function()? _onSpeechEnded;
  final void Function(Object error, StackTrace stackTrace)? _onTurnError;
  final VoiceInteractionResponseDecoder _responseDecoder;
  final BargeInPolicy _bargeInPolicy;
  final Uuid _uuid;
  final DateTime Function() _clock;
  final StreamController<InteractionState> _states =
      StreamController<InteractionState>.broadcast();

  InteractionState _state;
  SpeechInputSession? _speechSession;
  StreamSubscription<SpeechInputEvent>? _speechEvents;
  Timer? _candidateTimer;
  int _sequence = 0;
  bool _disposed = false;

  InteractionState get state => _state;

  Stream<InteractionState> get states => _states.stream;

  /// Dispatches an event with a Coordinator-owned global sequence.
  ///
  /// [epoch] may be set to a captured older epoch when a producer reports a
  /// late result. The reducer will consume its sequence but discard its
  /// presentation effect.
  InteractionState dispatch(
    InteractionEvent Function(InteractionStamp stamp) build, {
    TurnId? turnId,
    ResponseEpoch? epoch,
    OperationId? operationId,
  }) {
    _ensureOpen();
    final stamp = InteractionStamp(
      sessionId: _state.sessionId,
      turnId: turnId ?? _state.activeTurnId,
      epoch: epoch ?? _state.responseEpoch,
      sequence: ++_sequence,
      operationId: operationId,
    );
    final next = reduce(_state, build(stamp));
    _state = next;
    _states.add(next);
    return next;
  }

  TurnId startTurn(InteractionInputOrigin origin) {
    final turnId = TurnId(_uuid.v4());
    dispatch(
      (stamp) => TurnStarted(stamp: stamp, origin: origin),
      turnId: turnId,
    );
    return turnId;
  }

  Future<void> startVoice() async {
    _ensureOpen();
    final input = _speechInput;
    if (input == null) {
      throw StateError('InteractionSession has no SpeechInput capability');
    }
    await stopVoice();

    final session = await input.start();
    if (_disposed) {
      await session.cancel();
      return;
    }

    // A pending HITL envelope resumes the existing turn. Speaking over an
    // active response also waits for BargeInCommitted before assigning a new
    // turn, so the old delivered prefix can be projected safely. Start the
    // native session first so a failed permission/model/runtime start cannot
    // leave a phantom voice turn in the reducer.
    if (_state.pendingInteraction == null &&
        !_isOutputActive(_state.outputLane)) {
      startTurn(InteractionInputOrigin.voice);
    }

    _speechSession = session;
    _speechEvents = session.events.listen(
      _onSpeechEvent,
      onError: (Object error, StackTrace stackTrace) {
        // The recognizer owns its lifecycle/error contract. The Coordinator
        // only exposes the error to the session stream through state-free
        // host logging; it must not turn an input error into a domain write.
      },
      cancelOnError: false,
    );
  }

  Future<void> stopVoice() async {
    final session = _speechSession;
    if (session == null) return;
    _speechSession = null;
    final events = _speechEvents;
    _speechEvents = null;
    try {
      await session.stop();
    } finally {
      await events?.cancel();
    }
  }

  void speechStarted({DateTime? startedAt}) {
    final outputWasActive = _isOutputActive(_state.outputLane);
    dispatch((stamp) => SpeechStarted(stamp: stamp));
    if (!outputWasActive) return;

    final candidateAt = startedAt ?? _clock();
    dispatch((stamp) => BargeInCandidate(stamp: stamp, startedAt: candidateAt));
    _onBargeInCandidate?.call();
    _candidateTimer?.cancel();
    _candidateTimer = Timer(_bargeInPolicy.minimumSpeechDuration, () {
      if (_state.bargeInPhase == BargeInPhase.candidate) {
        commitBargeIn(transcript: _state.transcript);
      }
    });
  }

  void speechStopped({DateTime? stoppedAt, Duration? duration}) {
    dispatch((stamp) => SpeechStopped(stamp: stamp));
    if (_state.bargeInPhase != BargeInPhase.candidate) return;

    final startedAt = _state.candidateStartedAt;
    final elapsed =
        duration ??
        (startedAt == null
            ? Duration.zero
            : (stoppedAt ?? _clock()).difference(startedAt));
    final effectiveElapsed = elapsed.isNegative ? Duration.zero : elapsed;
    if (_bargeInPolicy.shouldCommit(
      elapsed: effectiveElapsed,
      transcript: _state.transcript,
    )) {
      commitBargeIn(transcript: _state.transcript);
    } else {
      resolveFalseInterruption();
    }
  }

  void updateTranscript(String text, {required bool isFinal}) {
    dispatch(
      (stamp) => TranscriptUpdated(stamp: stamp, text: text, isFinal: isFinal),
    );
    if (_state.bargeInPhase == BargeInPhase.candidate &&
        _bargeInPolicy.hasValidTranscript(text)) {
      commitBargeIn(transcript: text);
    }
    if (isFinal && text.trim().isNotEmpty) {
      _commitSpeechInput(text);
    }
  }

  void _commitSpeechInput(String text) {
    unawaited(
      commitInput(text).then<void>(
        (_) {},
        onError: (Object error, StackTrace stackTrace) {
          _onTurnError?.call(error, stackTrace);
        },
      ),
    );
  }

  Future<void> commitInput(
    String text, {
    InteractionInputOrigin? origin,
    AiInteractionResponse? interactionResponse,
    CancelToken? cancelToken,
    String? systemContext,
    String? model,
    String? resumeTurnId,
  }) {
    final inputOrigin =
        origin ?? _state.inputOrigin ?? InteractionInputOrigin.voice;
    final pending = _state.pendingInteraction;
    final response =
        interactionResponse ??
        (pending == null ? null : _responseDecoder(pending, text));
    final accepted =
        pending == null ||
        (response != null && response.interactionId == pending.interactionId);
    dispatch(
      (stamp) => InputCommitted(
        stamp: stamp,
        text: text,
        origin: inputOrigin,
        interactionResponse: response,
      ),
    );
    if (!accepted) return Future<void>.value();

    final turnId = _state.activeTurnId;
    if (turnId == null) return Future<void>.value();
    final handler = _onTurnCommitted;
    if (handler == null) return Future<void>.value();
    return handler(
      InteractionTurnRequest(
        sessionId: _state.sessionId,
        turnId: turnId,
        epoch: _state.responseEpoch,
        text: text,
        origin: inputOrigin,
        cancelToken: cancelToken,
        systemContext: systemContext,
        model: model,
        interactionResponse: response,
        resumeTurnId: resumeTurnId ?? pending?.resumeToken,
      ),
    );
  }

  void agentStarted() => dispatch((stamp) => AgentStarted(stamp: stamp));

  void agentTextGenerated(String text) =>
      dispatch((stamp) => AgentTextGenerated(stamp: stamp, text: text));

  void agentToolStarted(OperationId operationId) => dispatch(
    (stamp) => AgentToolStarted(stamp: stamp, operationId: operationId),
    operationId: operationId,
  );

  void agentWaitingForInteraction(AiInteractionEnvelope interaction) =>
      dispatch(
        (stamp) =>
            AgentWaitingForInteraction(stamp: stamp, interaction: interaction),
      );

  void agentFinished() => dispatch((stamp) => AgentFinished(stamp: stamp));

  void agentFailed({String? code}) =>
      dispatch((stamp) => AgentFailed(stamp: stamp, code: code));

  void agentCancelled() => dispatch((stamp) => AgentCancelled(stamp: stamp));

  void queueOutputSegment(OutputSegment segment) =>
      dispatch((stamp) => OutputSegmentQueued(stamp: stamp, segment: segment));

  void outputPlaybackStarted() =>
      dispatch((stamp) => OutputPlaybackStarted(stamp: stamp));

  void outputSegmentDelivered(String segmentId) => dispatch(
    (stamp) => OutputSegmentDelivered(stamp: stamp, segmentId: segmentId),
  );

  void outputPlaybackStopped({required bool interrupted}) => dispatch(
    (stamp) => OutputPlaybackStopped(stamp: stamp, interrupted: interrupted),
  );

  /// Maps provider-neutral SpeechOutput events into the session reducer.
  ///
  /// The provider's own stamp is used for session/epoch correlation only;
  /// reducer ordering remains Coordinator-owned through [dispatch].
  void acceptSpeechOutputEvent(SpeechOutputEvent event) {
    if (_disposed ||
        event.stamp.sessionId != _state.sessionId ||
        event.stamp.epoch != _state.responseEpoch) {
      return;
    }
    switch (event) {
      case SpeechOutputStarted():
        outputPlaybackStarted();
      case SpeechOutputSegmentDelivered(:final segmentId):
        outputSegmentDelivered(segmentId);
      case SpeechOutputPaused():
        dispatch((stamp) => OutputPlaybackPaused(stamp: stamp));
      case SpeechOutputResumed():
        dispatch((stamp) => OutputPlaybackResumed(stamp: stamp));
      case SpeechOutputStopped(:final interrupted):
        outputPlaybackStopped(interrupted: interrupted);
    }
  }

  /// Consumes a provider session without exposing its stream to the reducer.
  Future<void> consumeSpeechOutput(Stream<SpeechOutputEvent> events) async {
    await for (final event in events) {
      acceptSpeechOutputEvent(event);
    }
  }

  void commitBargeIn({String transcript = ''}) {
    if (_state.bargeInPhase != BargeInPhase.candidate) return;
    _candidateTimer?.cancel();
    final staleEpoch = _state.responseEpoch;
    final nextTurnId = TurnId(_uuid.v4());
    dispatch(
      (stamp) => BargeInCommitted(
        stamp: stamp,
        nextTurnId: nextTurnId,
        initialTranscript: transcript,
      ),
    );
    _onEpochAdvanced?.call(staleEpoch);
  }

  void resolveFalseInterruption() {
    if (_state.bargeInPhase != BargeInPhase.candidate) return;
    _candidateTimer?.cancel();
    dispatch((stamp) => FalseInterruption(stamp: stamp));
    dispatch((stamp) => OutputPlaybackResumed(stamp: stamp));
    _onFalseInterruption?.call();
  }

  Future<void> close() async {
    if (_disposed) return;
    _disposed = true;
    _candidateTimer?.cancel();
    final session = _speechSession;
    _speechSession = null;
    final events = _speechEvents;
    _speechEvents = null;
    try {
      await session?.cancel();
    } finally {
      await events?.cancel();
      if (!_state.isClosed) {
        final stamp = InteractionStamp(
          sessionId: _state.sessionId,
          turnId: _state.activeTurnId,
          epoch: _state.responseEpoch,
          sequence: ++_sequence,
        );
        _state = reduce(_state, SessionClosed(stamp: stamp));
      }
      await _states.close();
    }
  }

  void _onSpeechEvent(SpeechInputEvent event) {
    if (_disposed) return;
    switch (event) {
      case SpeechInputSpeechStarted(:final startedAt):
        speechStarted(startedAt: startedAt);
      case SpeechInputSpeechStopped(:final stoppedAt, :final duration):
        speechStopped(stoppedAt: stoppedAt, duration: duration);
      case SpeechInputTranscript(:final text, :final isFinal):
        updateTranscript(text, isFinal: isFinal);
      case SpeechInputEnded():
        speechStopped();
        _onSpeechEnded?.call();
        break;
    }
  }

  static bool _isOutputActive(InteractionOutputLane lane) =>
      lane == InteractionOutputLane.synthesizing ||
      lane == InteractionOutputLane.playing;

  void _ensureOpen() {
    if (_disposed) throw StateError('InteractionSession is closed');
  }
}
