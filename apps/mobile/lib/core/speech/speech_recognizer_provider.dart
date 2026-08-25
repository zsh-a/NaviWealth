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

/// Whether the selected platform has a real system on-device recognizer
/// implementation. Web remains an explicit unsupported surface; native
/// non-Android platforms currently use local Zipformer instead.
final speechRecognizerSystemBackendAvailableProvider = Provider<bool>(
  (_) => implementation.supportsSystemOnDeviceBackend,
);

/// User-selectable speech backend. Android uses system on-device recognition
/// by default; other native platforms use local Zipformer until their native
/// system recognizer adapters exist.
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
  SpeechRecognizerBackendController(this._prefs)
    : super(_load(_prefs, _defaultBackend()));

  static const String _preferenceKey = 'naviwealth.speech.recognizer_backend';

  final SharedPreferences _prefs;

  static SpeechRecognizerBackend get platformDefault => _defaultBackend();

  static SpeechRecognizerBackend _defaultBackend() {
    if (kIsWeb || implementation.supportsSystemOnDeviceBackend) {
      return SpeechRecognizerBackend.systemOnDevice;
    }
    return SpeechRecognizerBackend.localZipformer;
  }

  static SpeechRecognizerBackend _load(
    SharedPreferences prefs,
    SpeechRecognizerBackend fallback,
  ) {
    final stored = switch (prefs.getString(_preferenceKey)) {
      'localZipformer' => SpeechRecognizerBackend.localZipformer,
      'systemOnDevice' => SpeechRecognizerBackend.systemOnDevice,
      _ => fallback,
    };
    if (stored == SpeechRecognizerBackend.systemOnDevice &&
        !kIsWeb &&
        !implementation.supportsSystemOnDeviceBackend) {
      return fallback;
    }
    return stored;
  }

  Future<void> setBackend(SpeechRecognizerBackend backend) async {
    final effective = kIsWeb
        ? SpeechRecognizerBackend.systemOnDevice
        : implementation.supportsSystemOnDeviceBackend ||
              backend == SpeechRecognizerBackend.localZipformer
        ? backend
        : SpeechRecognizerBackend.localZipformer;
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
