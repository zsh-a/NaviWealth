import 'package:flutter_test/flutter_test.dart';

import 'package:naviwealth/core/speech/speech_recognizer_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'defaults to system recognition and persists a backend choice',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final controller = SpeechRecognizerBackendController(prefs);
      addTearDown(controller.dispose);

      expect(controller.state, SpeechRecognizerBackend.systemOnDevice);

      await controller.setBackend(SpeechRecognizerBackend.localZipformer);

      expect(controller.state, SpeechRecognizerBackend.localZipformer);
      final reloaded = SpeechRecognizerBackendController(prefs);
      addTearDown(reloaded.dispose);
      expect(reloaded.state, SpeechRecognizerBackend.localZipformer);
    },
  );

  test(
    'unknown persisted values fall back to the safe system backend',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'naviwealth.speech.recognizer_backend': 'futureBackend',
      });
      final prefs = await SharedPreferences.getInstance();
      final controller = SpeechRecognizerBackendController(prefs);
      addTearDown(controller.dispose);

      expect(controller.state, SpeechRecognizerBackend.systemOnDevice);
    },
  );
}
