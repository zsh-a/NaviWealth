import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

typedef SystemTtsErrorHandler = void Function(dynamic message);

/// Minimal native TTS surface used by [SystemSpeechOutput]. Keeping the
/// plugin behind this seam makes callback ordering and failure cleanup
/// testable without a platform channel.
abstract interface class SystemTtsDriver {
  Future<void> awaitSpeakCompletion(bool awaitCompletion);

  Future<void> setLanguage(String language);

  Future<void> speak(String text);

  Future<void> pause();

  Future<void> stop();

  void setStartHandler(VoidCallback callback);

  void setCompletionHandler(VoidCallback callback);

  void setPauseHandler(VoidCallback callback);

  void setContinueHandler(VoidCallback callback);

  void setCancelHandler(VoidCallback callback);

  void setErrorHandler(SystemTtsErrorHandler callback);
}

final class FlutterTtsSystemTtsDriver implements SystemTtsDriver {
  FlutterTtsSystemTtsDriver(this._textToSpeech);

  final FlutterTts _textToSpeech;

  @override
  Future<void> awaitSpeakCompletion(bool awaitCompletion) async {
    await _textToSpeech.awaitSpeakCompletion(awaitCompletion);
  }

  @override
  Future<void> setLanguage(String language) async {
    await _textToSpeech.setLanguage(language);
  }

  @override
  Future<void> speak(String text) async {
    await _textToSpeech.speak(text);
  }

  @override
  Future<void> pause() async {
    await _textToSpeech.pause();
  }

  @override
  Future<void> stop() async {
    await _textToSpeech.stop();
  }

  @override
  void setStartHandler(VoidCallback callback) {
    _textToSpeech.setStartHandler(callback);
  }

  @override
  void setCompletionHandler(VoidCallback callback) {
    _textToSpeech.setCompletionHandler(callback);
  }

  @override
  void setPauseHandler(VoidCallback callback) {
    _textToSpeech.setPauseHandler(callback);
  }

  @override
  void setContinueHandler(VoidCallback callback) {
    _textToSpeech.setContinueHandler(callback);
  }

  @override
  void setCancelHandler(VoidCallback callback) {
    _textToSpeech.setCancelHandler(callback);
  }

  @override
  void setErrorHandler(SystemTtsErrorHandler callback) {
    _textToSpeech.setErrorHandler(callback);
  }
}
