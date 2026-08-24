import '../ai/session/delivery_ledger.dart';
import '../ai/session/interaction_ids.dart';

enum SpeechOutputAvailability { ready, unsupported }

class SpeechOutputStatus {
  const SpeechOutputStatus(this.availability, {this.reason});

  final SpeechOutputAvailability availability;
  final String? reason;

  bool get isReady => availability == SpeechOutputAvailability.ready;
}

final class SpeechOutputRequest {
  const SpeechOutputRequest({required this.stamp, required this.segment});

  final InteractionStamp stamp;
  final OutputSegment segment;
}

sealed class SpeechOutputEvent {
  const SpeechOutputEvent({required this.stamp});

  final InteractionStamp stamp;
}

final class SpeechOutputStarted extends SpeechOutputEvent {
  const SpeechOutputStarted({required super.stamp, required this.segmentId});

  final String segmentId;
}

final class SpeechOutputSegmentDelivered extends SpeechOutputEvent {
  const SpeechOutputSegmentDelivered({
    required super.stamp,
    required this.segmentId,
  });

  final String segmentId;
}

final class SpeechOutputPaused extends SpeechOutputEvent {
  const SpeechOutputPaused({required super.stamp});
}

final class SpeechOutputResumed extends SpeechOutputEvent {
  const SpeechOutputResumed({required super.stamp});
}

final class SpeechOutputStopped extends SpeechOutputEvent {
  const SpeechOutputStopped({required super.stamp, required this.interrupted});

  final bool interrupted;
}

abstract interface class SpeechOutputSession {
  Stream<SpeechOutputEvent> get events;

  Future<void> pause();

  Future<void> resume();

  Future<void> stop();

  Future<void> cancel();
}

/// Output capability used by the session Coordinator.
///
/// System TTS is the intended first implementation. Keeping this contract
/// separate lets a downloadable local TTS engine or a realtime engine attach
/// later without changing InteractionSession state or Agent semantics.
abstract interface class SpeechOutput {
  Future<SpeechOutputStatus> status();

  Future<SpeechOutputSession> speak(SpeechOutputRequest request);
}
