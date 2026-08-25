import 'dart:async';

enum SpeechRecognizerAvailability {
  ready,
  modelNotInstalled,
  permissionDenied,
  unsupported,
}

class SpeechRecognizerStatus {
  const SpeechRecognizerStatus(this.availability, {this.reason});

  final SpeechRecognizerAvailability availability;
  final String? reason;

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
}

enum SpeechRecognitionErrorCode {
  modelNotInstalled,
  permissionDenied,
  unsupported,
  recorderUnavailable,
  runtimeUnavailable,
  sessionBusy,
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
