import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'speech_capture.dart';
import 'speech_capture_stub.dart'
    if (dart.library.io) 'speech_capture_io.dart'
    as implementation;

/// Exposes the native hot-path capture capability without changing the
/// production Android [SpeechRecognizer] default. It is intentionally null
/// on Web and non-Android platforms until their native audio paths exist.
final speechCaptureProvider = Provider<SpeechCapture?>((ref) {
  return implementation.createSpeechCapture();
});
