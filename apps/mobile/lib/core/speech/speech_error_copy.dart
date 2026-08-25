import '../../l10n/gen/app_localizations.dart';
import 'speech_recognizer.dart';

/// UI copy for stable speech failure codes. Provider messages and exception
/// reasons intentionally never reach this function.
String speechRecognitionErrorMessage(
  AppLocalizations l10n,
  SpeechRecognitionErrorCode code,
) => switch (code) {
  SpeechRecognitionErrorCode.modelNotInstalled => l10n.speechInputModelMissing,
  SpeechRecognitionErrorCode.permissionDenied =>
    l10n.speechInputPermissionDenied,
  SpeechRecognitionErrorCode.unsupported => l10n.speechInputUnsupported,
  SpeechRecognitionErrorCode.recorderUnavailable =>
    l10n.speechInputRecorderUnavailable,
  SpeechRecognitionErrorCode.runtimeUnavailable =>
    l10n.speechInputRuntimeUnavailable,
  SpeechRecognitionErrorCode.sessionBusy => l10n.speechInputSessionBusy,
};
