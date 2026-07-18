import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../logging/providers.dart';
import 'managed_speech_recognizer.dart';
import 'speech_diagnostics.dart';
import 'speech_recognizer.dart';
import 'speech_recognizer_stub.dart'
    if (dart.library.io) 'speech_recognizer_sherpa.dart'
    as implementation;

final speechDiagnosticsProvider = Provider<SpeechDiagnosticsRecorder>((ref) {
  return SpeechDiagnosticsRecorder(logger: ref.watch(loggerProvider));
});

final speechRecognizerProvider = Provider<SpeechRecognizer>((ref) {
  return ManagedSpeechRecognizer(
    delegate: implementation.createSpeechRecognizer(ref),
    diagnostics: ref.watch(speechDiagnosticsProvider),
  );
});
