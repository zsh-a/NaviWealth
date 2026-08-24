import 'dart:io';

import 'speech_capture.dart';
import 'speech_capture_android.dart';

SpeechCapture? createSpeechCapture() {
  if (Platform.isAndroid) return AndroidNativeAudioCapture();
  return null;
}
