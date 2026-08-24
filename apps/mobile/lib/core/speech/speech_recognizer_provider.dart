import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../design_system/preferences/theme_preferences.dart';
import '../logging/providers.dart';
import 'managed_speech_recognizer.dart';
import 'speech_diagnostics.dart';
import 'speech_input.dart';
import 'speech_recognizer.dart';
import 'speech_recognizer_stub.dart'
    if (dart.library.io) 'speech_recognizer_io.dart'
    as implementation;

enum SpeechRecognizerBackend { systemOnDevice, localZipformer }

/// User-selectable speech backend. System on-device recognition is the safe
/// default; the local Zipformer backend is opt-in and stays on this device.
final speechRecognizerBackendProvider =
    StateNotifierProvider<
      SpeechRecognizerBackendController,
      SpeechRecognizerBackend
    >(
      (ref) => SpeechRecognizerBackendController(
        ref.watch(sharedPreferencesProvider),
      ),
    );

class SpeechRecognizerBackendController
    extends StateNotifier<SpeechRecognizerBackend> {
  SpeechRecognizerBackendController(this._prefs) : super(_load(_prefs));

  static const String _preferenceKey = 'naviwealth.speech.recognizer_backend';

  final SharedPreferences _prefs;

  static SpeechRecognizerBackend _load(SharedPreferences prefs) {
    if (kIsWeb) return SpeechRecognizerBackend.systemOnDevice;
    return switch (prefs.getString(_preferenceKey)) {
      'localZipformer' => SpeechRecognizerBackend.localZipformer,
      _ => SpeechRecognizerBackend.systemOnDevice,
    };
  }

  Future<void> setBackend(SpeechRecognizerBackend backend) async {
    final effective = kIsWeb ? SpeechRecognizerBackend.systemOnDevice : backend;
    if (state == effective) return;
    state = effective;
    await _prefs.setString(_preferenceKey, effective.name);
  }
}

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
