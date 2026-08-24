/// Policy helpers for the two-phase voice interruption decision.
///
/// VAD may produce a candidate immediately so playback can be ducked, but a
/// response epoch is not invalidated until the candidate has enough acoustic
/// duration or a non-empty transcript.
final class BargeInPolicy {
  const BargeInPolicy({
    this.minimumSpeechDuration = const Duration(milliseconds: 180),
  });

  final Duration minimumSpeechDuration;

  bool hasValidTranscript(String transcript) => transcript.trim().isNotEmpty;

  bool shouldCommit({required Duration elapsed, required String transcript}) =>
      elapsed >= minimumSpeechDuration || hasValidTranscript(transcript);
}
