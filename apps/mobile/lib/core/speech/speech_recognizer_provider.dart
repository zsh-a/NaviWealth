import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../logging/providers.dart';
import 'managed_speech_recognizer.dart';
import 'speech_diagnostics.dart';
import 'speech_input.dart';
import 'speech_recognizer.dart';
import 'speech_recognizer_stub.dart'
    if (dart.library.io) 'speech_recognizer_io.dart'
    as implementation;

enum SpeechRecognizerBackend { systemOnDevice, localZipformer }

/// System on-device recognition is deliberately the safe default. Settings
/// may override this provider after the local model has been downloaded.
final speechRecognizerBackendProvider = Provider<SpeechRecognizerBackend>((
  ref,
) {
  return SpeechRecognizerBackend.systemOnDevice;
});

final speechDiagnosticsProvider = Provider<SpeechDiagnosticsRecorder>((ref) {
  return SpeechDiagnosticsRecorder(logger: ref.watch(loggerProvider));
});

final speechRecognizerProvider = Provider<SpeechRecognizer>((ref) {
  final backend = ref.watch(speechRecognizerBackendProvider);
  final delegate = switch (backend) {
    SpeechRecognizerBackend.systemOnDevice =>
      implementation.createSpeechRecognizer(ref),
    SpeechRecognizerBackend.localZipformer =>
      implementation.createLocalSpeechRecognizer(ref),
  };
  return ManagedSpeechRecognizer(
    delegate: delegate,
    diagnostics: ref.watch(speechDiagnosticsProvider),
  );
});

final speechInputProvider = Provider<SpeechInput>((ref) {
  return RecognizerSpeechInput(ref.watch(speechRecognizerProvider));
});
