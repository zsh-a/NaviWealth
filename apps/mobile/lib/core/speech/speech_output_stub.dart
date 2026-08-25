import 'speech_output.dart';

SpeechOutput createSpeechOutput() => const _UnsupportedSpeechOutput();

final class _UnsupportedSpeechOutput implements SpeechOutput {
  const _UnsupportedSpeechOutput();

  @override
  Future<SpeechOutputStatus> status() async => const SpeechOutputStatus(
    SpeechOutputAvailability.unsupported,
    reason: 'Speech output is unavailable on this platform',
  );

  @override
  Future<SpeechOutputSession> speak(SpeechOutputRequest request) {
    throw const SpeechOutputException(
      SpeechOutputErrorCode.engineUnavailable,
      'Speech output is unavailable on this platform',
    );
  }
}
