import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'speech_recognizer.dart';
import 'speech_recognizer_stub.dart'
    if (dart.library.io) 'speech_recognizer_sherpa.dart'
    as implementation;

final speechRecognizerProvider = Provider<SpeechRecognizer>((ref) {
  return implementation.createSpeechRecognizer(ref);
});
