import 'package:flutter_test/flutter_test.dart';

import 'package:naviwealth/core/speech/speech_recognizer_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'defaults to the platform backend and persists a backend choice',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final controller = SpeechRecognizerBackendController(prefs);
      addTearDown(controller.dispose);

      expect(
        controller.state,
        SpeechRecognizerBackendController.platformDefault,
      );

      await controller.setBackend(SpeechRecognizerBackend.localZipformer);

      expect(controller.state, SpeechRecognizerBackend.localZipformer);
      final reloaded = SpeechRecognizerBackendController(prefs);
      addTearDown(reloaded.dispose);
      expect(reloaded.state, SpeechRecognizerBackend.localZipformer);
    },
  );

  test('unknown persisted values fall back to the platform backend', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'naviwealth.speech.recognizer_backend': 'futureBackend',
    });
    final prefs = await SharedPreferences.getInstance();
    final controller = SpeechRecognizerBackendController(prefs);
    addTearDown(controller.dispose);

    expect(controller.state, SpeechRecognizerBackendController.platformDefault);
  });

  test(
    'migrates an unavailable persisted system backend to the platform default',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'naviwealth.speech.recognizer_backend': 'systemOnDevice',
      });
      final prefs = await SharedPreferences.getInstance();
      final controller = SpeechRecognizerBackendController(prefs);
      addTearDown(controller.dispose);

      expect(
        controller.state,
        SpeechRecognizerBackendController.platformDefault,
      );
    },
  );
}
