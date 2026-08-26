import 'dart:async';

enum SpeechRecognizerAvailability {
  ready,
  modelNotInstalled,
  permissionDenied,
  unsupported,
}

/// Runtime capabilities of the selected speech input path.
///
/// These flags describe the path that owns the microphone and its timing
/// signals; they are not a second ASR/provider abstraction. In particular,
/// [fullDuplex] is only true when capture can remain active while the
/// interaction session is presenting TTS and [supportsBargeIn] means that the
/// path emits enough semantic boundary information to interrupt that output.
final class SpeechRecognizerCapabilities {
  const SpeechRecognizerCapabilities({
    this.supportsBargeIn = false,
    this.nativeAudioPath = false,
    this.vad = false,
    this.fullDuplex = false,
  });

  static const unknown = SpeechRecognizerCapabilities();

  /// Whether speech events can be used to pause and supersede active output.
  final bool supportsBargeIn;

  /// Whether high-rate microphone processing stays on a native audio path.
  final bool nativeAudioPath;

  /// Whether the path emits native speech start/stop boundaries.
  final bool vad;

  /// Whether input and output may remain active in the same interaction turn.
  final bool fullDuplex;
}

class SpeechRecognizerStatus {
  const SpeechRecognizerStatus(
    this.availability, {
    this.reason,
    this.capabilities = SpeechRecognizerCapabilities.unknown,
  });

  final SpeechRecognizerAvailability availability;
  final String? reason;
  final SpeechRecognizerCapabilities capabilities;

  bool get isReady => availability == SpeechRecognizerAvailability.ready;

  /// The stable error represented by this status, or null when the engine is
  /// ready. The optional [reason] is provider-owned diagnostic text and must
  /// not be used as a user-facing or logged error identifier.
  SpeechRecognitionErrorCode? get errorCode => availability.errorCode;
}

class SpeechRecognitionEvent {
  const SpeechRecognitionEvent({
    required this.text,
    required this.isFinal,
    this.speechStarted = false,
    this.startedAt,
    this.speechStopped = false,
    this.stoppedAt,
    this.speechDuration,
    this.captureStarted = false,
    this.captureStartupDuration,
    this.sessionEnded = false,
    this.cancelled = false,
  });

  final String text;
  final bool isFinal;

  /// True when the native capture pipeline detected speech before ASR had a
  /// transcript. This is a semantic signal for InteractionSession barge-in;
  /// it does not carry audio frames.
  final bool speechStarted;

  final DateTime? startedAt;

  /// True when the native capture pipeline reached a VAD speech boundary.
  /// This is distinct from the end of the whole recognition session.
  final bool speechStopped;

  final DateTime? stoppedAt;
  final Duration? speechDuration;

  /// True when the native capture pipeline has completed its startup work and
  /// AudioRecord is accepting frames. This is distinct from
  /// [speechStarted], which waits for VAD to detect a user's voice.
  final bool captureStarted;

  /// Time spent preparing the native capture/model path before
  /// [captureStarted]. This is transcript-free startup telemetry.
  final Duration? captureStartupDuration;

  /// True when the provider has emitted its terminal lifecycle signal. This
  /// is separate from [isFinal]: a native session can end because the host
  /// went into the background without producing a final transcript.
  final bool sessionEnded;

  /// Whether [sessionEnded] was caused by cancellation rather than a normal
  /// provider endpoint.
  final bool cancelled;
}

enum SpeechRecognitionErrorCode {
  modelNotInstalled,
  permissionDenied,
  unsupported,
  recorderUnavailable,
  runtimeUnavailable,
  sessionBusy,
}

/// Optional preparation capability for recognizers with a heavyweight local
/// runtime. Preparation must not start microphone capture or request a
/// permission; it only makes the next [SpeechRecognizer.start] faster.
abstract interface class SpeechRecognizerPreparation {
  Future<void> prepare();
}

/// Optional cancellation seam for a start which is still waiting on native
/// permission, model loading, or recognizer construction.
abstract interface class SpeechRecognizerPendingStartCancellation {
  Future<void> cancelPendingStart();
}

extension SpeechRecognizerAvailabilityCode on SpeechRecognizerAvailability {
  SpeechRecognitionErrorCode? get errorCode => switch (this) {
    SpeechRecognizerAvailability.ready => null,
    SpeechRecognizerAvailability.modelNotInstalled =>
      SpeechRecognitionErrorCode.modelNotInstalled,
    SpeechRecognizerAvailability.permissionDenied =>
      SpeechRecognitionErrorCode.permissionDenied,
    SpeechRecognizerAvailability.unsupported =>
      SpeechRecognitionErrorCode.unsupported,
  };

  /// Stable, privacy-safe identifier for diagnostics and tests.
  String get diagnosticCode => switch (this) {
    SpeechRecognizerAvailability.ready => 'ready',
    SpeechRecognizerAvailability.modelNotInstalled => 'model_not_installed',
    SpeechRecognizerAvailability.permissionDenied => 'permission_denied',
    SpeechRecognizerAvailability.unsupported => 'unsupported',
  };
}

extension SpeechRecognitionErrorCodeValue on SpeechRecognitionErrorCode {
  /// Stable, privacy-safe identifier. Do not replace this with provider error
  /// strings: those can contain device-specific or user-specific details.
  String get diagnosticCode => switch (this) {
    SpeechRecognitionErrorCode.modelNotInstalled => 'model_not_installed',
    SpeechRecognitionErrorCode.permissionDenied => 'permission_denied',
    SpeechRecognitionErrorCode.unsupported => 'unsupported',
    SpeechRecognitionErrorCode.recorderUnavailable => 'recorder_unavailable',
    SpeechRecognitionErrorCode.runtimeUnavailable => 'runtime_unavailable',
    SpeechRecognitionErrorCode.sessionBusy => 'session_busy',
  };
}

/// Converts an unavailable status into a stable exception without carrying the
/// provider's free-form [SpeechRecognizerStatus.reason] into the app surface.
SpeechRecognitionException speechRecognitionExceptionForStatus(
  SpeechRecognizerStatus status,
) {
  final code = status.errorCode;
  if (code == null) {
    throw ArgumentError.value(status, 'status', 'The recognizer is ready');
  }
  return SpeechRecognitionException(code, _stableMessageForError(code));
}

String _stableMessageForError(SpeechRecognitionErrorCode code) =>
    switch (code) {
      SpeechRecognitionErrorCode.modelNotInstalled =>
        'The speech recognition model is not installed',
      SpeechRecognitionErrorCode.permissionDenied =>
        'Microphone permission was denied',
      SpeechRecognitionErrorCode.unsupported =>
        'Speech recognition is unavailable on this platform',
      SpeechRecognitionErrorCode.recorderUnavailable =>
        'The microphone recorder is unavailable',
      SpeechRecognitionErrorCode.runtimeUnavailable =>
        'The speech recognition runtime is unavailable',
      SpeechRecognitionErrorCode.sessionBusy =>
        'Another speech recognition session is already active',
    };

class SpeechRecognitionException implements Exception {
  const SpeechRecognitionException(this.code, this.message, {this.cause});

  final SpeechRecognitionErrorCode code;
  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

abstract interface class SpeechRecognitionSession {
  Stream<SpeechRecognitionEvent> get events;

  Future<void> stop();

  Future<void> cancel();
}

abstract interface class SpeechRecognizer {
  Future<SpeechRecognizerStatus> status();

  Future<SpeechRecognitionSession> start();
}
