import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'speech_recognizer.dart';

/// Web and other non-IO builds do not expose Android's system recognizer.
bool get supportsSystemOnDeviceBackend => false;

SpeechRecognizer createSpeechRecognizer(Ref ref) =>
    const _UnsupportedSpeechRecognizer();

SpeechRecognizer createLocalSpeechRecognizer(Ref ref) =>
    const _UnsupportedSpeechRecognizer();

class _UnsupportedSpeechRecognizer implements SpeechRecognizer {
  const _UnsupportedSpeechRecognizer();

  @override
  Future<SpeechRecognizerStatus> status() async => const SpeechRecognizerStatus(
    SpeechRecognizerAvailability.unsupported,
    reason: 'Speech recognition is unavailable on this platform',
    capabilities: SpeechRecognizerCapabilities.unknown,
  );

  @override
  Future<SpeechRecognitionSession> start() {
    throw const SpeechRecognitionException(
      SpeechRecognitionErrorCode.runtimeUnavailable,
      'Speech recognition is unavailable on this platform',
    );
  }
}
