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
import '../../core/speech/speech_recognizer.dart';
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

typedef InteractionTurnHandler = Future<void> Function(
  InteractionTurnRequest request,
);

typedef SpeechStatusHandler = void Function(SpeechRecognizerStatus status);

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
    void Function({required bool cancelled})? onSpeechEnded,
    SpeechStatusHandler? onSpeechStatus,
    void Function(Duration? startupDuration)? onSpeechCaptureStarted,
    Future<void> Function()? onNonDuplexVoiceStart,
    void Function(SpeechRecognitionException error, StackTrace stackTrace)?
    onSpeechError,
    void Function(InteractionState state)? onStateChanged,
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
       _onSpeechStatus = onSpeechStatus,
       _onSpeechCaptureStarted = onSpeechCaptureStarted,
       _onNonDuplexVoiceStart = onNonDuplexVoiceStart,
       _onSpeechError = onSpeechError,
       _onStateChanged = onStateChanged,
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
  final void Function({required bool cancelled})? _onSpeechEnded;
  final SpeechStatusHandler? _onSpeechStatus;
  final void Function(Duration? startupDuration)? _onSpeechCaptureStarted;
  final Future<void> Function()? _onNonDuplexVoiceStart;
  final void Function(SpeechRecognitionException error, StackTrace stackTrace)?
  _onSpeechError;
  final void Function(InteractionState state)? _onStateChanged;
  final void Function(Object error, StackTrace stackTrace)? _onTurnError;
  final VoiceInteractionResponseDecoder _responseDecoder;
  final BargeInPolicy _bargeInPolicy;
  final Uuid _uuid;
  final DateTime Function() _clock;
  final StreamController<InteractionState> _states =
      StreamController<InteractionState>.broadcast();

  InteractionState _state;
  SpeechRecognizerCapabilities _speechCapabilities =
      SpeechRecognizerCapabilities.unknown;
  SpeechInputSession? _speechSession;
  StreamSubscription<SpeechInputEvent>? _speechEvents;
  Timer? _candidateTimer;
  int _sequence = 0;
  bool _disposed = false;
  Future<void>? _voiceStartFuture;
  bool _voiceStartCancellationRequested = false;

  static const _statusTimeout = Duration(seconds: 3);
  static const _startupTimeout = Duration(seconds: 10);
  static const _retryDelay = Duration(milliseconds: 80);

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
    _onStateChanged?.call(next);
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

  /// Opens the next voice Turn inside a native full-duplex session.
  ///
  /// The microphone session intentionally remains alive across turns. The
  /// old response epoch is still invalidated and cancelled so generated text
  /// or TTS that belongs to the previous utterance cannot leak into the new
  /// response.
  void _startNextVoiceTurn() {
    final staleEpoch = _state.responseEpoch;
    startTurn(InteractionInputOrigin.voice);
    _onEpochAdvanced?.call(staleEpoch);
  }

  Future<void> startVoice() {
    _ensureOpen();
    final inFlight = _voiceStartFuture;
    if (inFlight != null) return inFlight;
    final input = _speechInput;
    if (input == null) {
      throw StateError('InteractionSession has no SpeechInput capability');
    }
    _voiceStartCancellationRequested = false;
    final future = _startVoiceInternal(input);
    _voiceStartFuture = future;
    return future.whenComplete(() {
      if (identical(_voiceStartFuture, future)) _voiceStartFuture = null;
    });
  }

  Future<void> _startVoiceInternal(SpeechInput input) async {
    await _endVoice(cancelled: false);
    if (_voiceStartCancellationRequested || _disposed) {
      _onSpeechEnded?.call(cancelled: true);
      return;
    }

    SpeechRecognizerStatus status;
    try {
      status = await input.status().timeout(_statusTimeout);
    } on TimeoutException catch (error, stackTrace) {
      final failure = SpeechRecognitionException(
        SpeechRecognitionErrorCode.runtimeUnavailable,
        'Speech recognition status timed out',
        cause: error,
      );
      _onSpeechError?.call(failure, stackTrace);
      Error.throwWithStackTrace(failure, stackTrace);
    }
    _speechCapabilities = status.capabilities;
    _onSpeechStatus?.call(status);
    if (!status.isReady &&
        status.availability != SpeechRecognizerAvailability.permissionDenied) {
      throw speechRecognitionExceptionForStatus(status);
    }
    if (_voiceStartCancellationRequested || _disposed) {
      _onSpeechEnded?.call(cancelled: true);
      return;
    }

    final outputWasActive = _isOutputActive(_state.outputLane);
    final staleOutputEpoch = _state.responseEpoch;
    if (outputWasActive && !status.capabilities.fullDuplex) {
      // System recognition is intentionally push-to-talk. Stop the current
      // utterance before opening a second platform-owned microphone session;
      // Zipformer advertises full duplex and keeps the barge-in candidate path.
      await _onNonDuplexVoiceStart?.call();
    }

    SpeechInputSession? session;
    Object? lastError;
    StackTrace? lastStackTrace;
    for (var attempt = 0; attempt < 2; attempt++) {
      if (_voiceStartCancellationRequested || _disposed) {
        _onSpeechEnded?.call(cancelled: true);
        return;
      }
      try {
        final pendingStart = input.start();
        try {
          session = await pendingStart.timeout(_startupTimeout);
        } on TimeoutException catch (error, stackTrace) {
          unawaited(_cancelPendingStart(input));
          unawaited(_cancelLateInputStart(pendingStart));
          final failure = SpeechRecognitionException(
            SpeechRecognitionErrorCode.runtimeUnavailable,
            'Speech recognition startup timed out',
            cause: error,
          );
          Error.throwWithStackTrace(failure, stackTrace);
        }
        break;
      } on Object catch (error, stackTrace) {
        if (_voiceStartCancellationRequested || _disposed) {
          _onSpeechEnded?.call(cancelled: true);
          return;
        }
        lastError = error;
        lastStackTrace = stackTrace;
        if (attempt == 0 && _isRetryableSpeechStart(error)) {
          await _cancelPendingStart(input);
          await Future<void>.delayed(_retryDelay);
          continue;
        }
        Error.throwWithStackTrace(error, stackTrace);
      }
    }
    if (session == null) {
      Error.throwWithStackTrace(
        lastError ??
            const SpeechRecognitionException(
              SpeechRecognitionErrorCode.runtimeUnavailable,
              'Speech recognition failed to start',
            ),
        lastStackTrace ?? StackTrace.current,
      );
    }
    if (_voiceStartCancellationRequested || _disposed) {
      await session.cancel();
      _onSpeechEnded?.call(cancelled: true);
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
      if (outputWasActive && !status.capabilities.fullDuplex) {
        // Push-to-talk had to stop the old utterance before opening the
        // platform-owned recorder. Treat that as a real voice interruption so
        // the old Agent request is cancelled as well, not merely hidden from
        // TTS by the output suppression fence.
        _onEpochAdvanced?.call(staleOutputEpoch);
      }
    }

    _speechSession = session;
    _speechEvents = session.events.listen(
      _onSpeechEvent,
      onError: (Object error, StackTrace stackTrace) {
        final normalized = error is SpeechRecognitionException
            ? error
            : SpeechRecognitionException(
                SpeechRecognitionErrorCode.runtimeUnavailable,
                'Speech recognition event stream failed',
                cause: error,
              );
        try {
          _onSpeechError?.call(normalized, stackTrace);
        } catch (_) {
          // Diagnostics must never make the input lifecycle load-bearing.
        }
      },
      cancelOnError: false,
    );
  }

  Future<void> _cancelPendingStart(SpeechInput input) async {
    if (input case final SpeechInputPendingStartCancellation cancellation) {
      try {
        await cancellation.cancelPendingStart();
      } on Object {
        // The subsequent typed start error remains the source of truth.
      }
    }
  }

  Future<void> _cancelLateInputStart(Future<SpeechInputSession> pending) async {
    try {
      await (await pending).cancel();
    } on Object {
      // The startup timeout already released the caller; clean up late native
      // resources when the platform eventually returns them.
    }
  }

  static bool _isRetryableSpeechStart(Object error) =>
      error is SpeechRecognitionException &&
      switch (error.code) {
        SpeechRecognitionErrorCode.recorderUnavailable ||
        SpeechRecognitionErrorCode.runtimeUnavailable ||
        SpeechRecognitionErrorCode.sessionBusy => true,
        _ => false,
      };

  Future<void> stopVoice() async {
    await _endVoice(cancelled: false);
  }

  Future<void> cancelVoice() async {
    final starting = _voiceStartFuture;
    if (starting != null) {
      _voiceStartCancellationRequested = true;
      final input = _speechInput;
      if (input != null) await _cancelPendingStart(input);
      try {
        await starting;
      } on Object {
        // Cancellation is user intent; the controller should not surface the
        // native start failure after the user has already cancelled.
      }
      return;
    }
    await _endVoice(cancelled: true);
  }

  Future<void> _endVoice({required bool cancelled}) async {
    final session = _speechSession;
    if (session == null) return;
    _speechSession = null;
    final events = _speechEvents;
    _speechEvents = null;
    try {
      if (cancelled) {
        await session.cancel();
      } else {
        await session.stop();
      }
    } finally {
      await events?.cancel();
    }
  }

  void speechStarted({DateTime? startedAt}) {
    final outputWasActive = _isOutputActive(_state.outputLane);
    if (!outputWasActive &&
        _speechCapabilities.fullDuplex &&
        _state.activeTurnId != null &&
        _state.inputOrigin == InteractionInputOrigin.voice &&
        _state.inputLane == InteractionInputLane.committed &&
        _state.pendingInteraction == null) {
      _startNextVoiceTurn();
    }
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
    if (isFinal &&
        !(_state.bargeInPhase == BargeInPhase.candidate) &&
        _speechCapabilities.fullDuplex &&
        _state.activeTurnId != null &&
        _state.inputOrigin == InteractionInputOrigin.voice &&
        _state.inputLane == InteractionInputLane.committed &&
        _state.pendingInteraction == null &&
        text.trim().isNotEmpty &&
        text.trim() != _state.lastCommittedText?.trim()) {
      // Some recognizers can produce a final segment without a separate VAD
      // start event. Keep the turn boundary correct in that case as well.
      _startNextVoiceTurn();
    }
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
      case SpeechOutputError():
        // SerializedSpeechOutputBridge reports provider failures separately;
        // an error event never counts as delivered assistant output.
        break;
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
    _voiceStartCancellationRequested = true;
    final starting = _voiceStartFuture;
    if (starting != null) {
      final input = _speechInput;
      if (input != null) await _cancelPendingStart(input);
      try {
        await starting;
      } on Object {
        // Closing the host is itself a cancellation boundary.
      }
    }
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
      case SpeechInputCaptureStarted(:final startupDuration):
        _onSpeechCaptureStarted?.call(startupDuration);
        break;
      case SpeechInputTranscript(:final text, :final isFinal):
        updateTranscript(text, isFinal: isFinal);
      case SpeechInputEnded(:final cancelled):
        // Explicit/native cancellation must discard an unfinished candidate.
        // Treating it as a normal endpoint could commit a new response epoch
        // while the Activity is going into the background or the user is
        // deliberately cancelling dictation.
        if (cancelled) {
          resolveFalseInterruption();
        } else {
          speechStopped();
        }
        _onSpeechEnded?.call(cancelled: cancelled);
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
