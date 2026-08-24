import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'speech_recognizer.dart';
import 'speech_recognizer_android.dart';
import 'speech_recognizer_sherpa.dart' as sherpa;

/// Selects the current native speech backend without changing the shared
/// SpeechRecognizer contract. Android uses the platform's explicit on-device
/// recognizer; other IO platforms retain the local sherpa backend until their
/// native audio path is implemented.
SpeechRecognizer createSpeechRecognizer(Ref ref) {
  if (Platform.isAndroid) return AndroidOnDeviceSpeechRecognizer();
  return sherpa.createSpeechRecognizer(ref);
}
