import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'speech_recognizer.dart';

SpeechRecognizer createSpeechRecognizer(Ref ref) =>
    const _UnsupportedSpeechRecognizer();

class _UnsupportedSpeechRecognizer implements SpeechRecognizer {
  const _UnsupportedSpeechRecognizer();

  @override
  Future<SpeechRecognizerStatus> status() async => const SpeechRecognizerStatus(
    SpeechRecognizerAvailability.unsupported,
    reason: 'Speech recognition is unavailable on this platform',
  );

  @override
  Future<SpeechRecognitionSession> start() {
    throw const SpeechRecognitionException(
      SpeechRecognitionErrorCode.runtimeUnavailable,
      'Speech recognition is unavailable on this platform',
    );
  }
}
