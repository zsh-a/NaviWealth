import 'dart:async';

enum SpeechRecognizerAvailability { ready, modelNotInstalled, unsupported }

class SpeechRecognizerStatus {
  const SpeechRecognizerStatus(this.availability, {this.reason});

  final SpeechRecognizerAvailability availability;
  final String? reason;

  bool get isReady => availability == SpeechRecognizerAvailability.ready;
}

class SpeechRecognitionEvent {
  const SpeechRecognitionEvent({required this.text, required this.isFinal});

  final String text;
  final bool isFinal;
}

enum SpeechRecognitionErrorCode {
  modelNotInstalled,
  permissionDenied,
  recorderUnavailable,
  runtimeUnavailable,
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
