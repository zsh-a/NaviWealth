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
}

class SpeechRecognitionEvent {
  const SpeechRecognitionEvent({
    required this.text,
    required this.isFinal,
    this.speechStarted = false,
    this.startedAt,
  });

  final String text;
  final bool isFinal;

  /// True when the native capture pipeline detected speech before ASR had a
  /// transcript. This is a semantic signal for InteractionSession barge-in;
  /// it does not carry audio frames.
  final bool speechStarted;

  final DateTime? startedAt;
}

enum SpeechRecognitionErrorCode {
  modelNotInstalled,
  permissionDenied,
  recorderUnavailable,
  runtimeUnavailable,
  sessionBusy,
}

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
