import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ai/local/embedding/model_install_paths.dart';
import 'speech_recognizer.dart';
import 'speech_recognizer_android.dart';
import 'speech_recognizer_sherpa.dart' as sherpa;
import 'speech_recognizer_sherpa_android.dart';

/// The explicit system on-device bridge currently exists only on Android.
/// Other native platforms use the local Zipformer path until a native
/// platform recognizer adapter is implemented for them.
bool get supportsSystemOnDeviceBackend => Platform.isAndroid;

/// Selects the current native speech backend without changing the shared
/// SpeechRecognizer contract. Android uses the platform's explicit on-device
/// recognizer; other IO platforms retain the local sherpa backend until their
/// native audio path is implemented.
SpeechRecognizer createSpeechRecognizer(Ref ref) {
  if (Platform.isAndroid) return AndroidOnDeviceSpeechRecognizer();
  return sherpa.createSpeechRecognizer(ref);
}

/// Builds the opt-in Android local-model backend. The default factory above
/// intentionally remains the system on-device recognizer.
SpeechRecognizer createLocalSpeechRecognizer(Ref ref) {
  if (Platform.isAndroid) {
    return AndroidSherpaSpeechRecognizer(
      resolvePaths: () => ref.read(modelInstallPathsProvider.future),
    );
  }
  return sherpa.createSpeechRecognizer(ref);
}
