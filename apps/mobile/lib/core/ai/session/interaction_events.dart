import '../contracts/interaction.dart';
import 'delivery_ledger.dart';
import 'interaction_ids.dart';
import 'interaction_state.dart';

sealed class InteractionEvent {
  const InteractionEvent({required this.stamp});

  final InteractionStamp stamp;
}

final class TurnStarted extends InteractionEvent {
  const TurnStarted({required super.stamp, required this.origin});

  final InteractionInputOrigin origin;
}

final class SpeechStarted extends InteractionEvent {
  const SpeechStarted({required super.stamp});
}

final class SpeechStopped extends InteractionEvent {
  const SpeechStopped({required super.stamp});
}

final class TranscriptUpdated extends InteractionEvent {
  const TranscriptUpdated({
    required super.stamp,
    required this.text,
    required this.isFinal,
  });

  final String text;
  final bool isFinal;
}

final class InputCommitted extends InteractionEvent {
  const InputCommitted({
    required super.stamp,
    required this.text,
    required this.origin,
    this.interactionResponse,
  });

  final String text;
  final InteractionInputOrigin origin;
  final AiInteractionResponse? interactionResponse;
}

final class AgentStarted extends InteractionEvent {
  const AgentStarted({required super.stamp});
}

final class AgentToolStarted extends InteractionEvent {
  const AgentToolStarted({required super.stamp, required this.operationId});

  final OperationId operationId;
}

final class AgentWaitingForInteraction extends InteractionEvent {
  const AgentWaitingForInteraction({
    required super.stamp,
    required this.interaction,
  });

  final AiInteractionEnvelope interaction;
}

final class AgentTextGenerated extends InteractionEvent {
  const AgentTextGenerated({required super.stamp, required this.text});

  final String text;
}

final class OutputSegmentQueued extends InteractionEvent {
  const OutputSegmentQueued({required super.stamp, required this.segment});

  final OutputSegment segment;
}

final class OutputPlaybackStarted extends InteractionEvent {
  const OutputPlaybackStarted({required super.stamp});
}

final class OutputSegmentDelivered extends InteractionEvent {
  const OutputSegmentDelivered({required super.stamp, required this.segmentId});

  final String segmentId;
}

final class OutputPlaybackPaused extends InteractionEvent {
  const OutputPlaybackPaused({required super.stamp});
}

final class OutputPlaybackResumed extends InteractionEvent {
  const OutputPlaybackResumed({required super.stamp});
}

final class OutputPlaybackStopped extends InteractionEvent {
  const OutputPlaybackStopped({
    required super.stamp,
    required this.interrupted,
  });

  final bool interrupted;
}

final class BargeInCandidate extends InteractionEvent {
  const BargeInCandidate({required super.stamp, required this.startedAt});

  final DateTime startedAt;
}

final class BargeInCommitted extends InteractionEvent {
  const BargeInCommitted({
    required super.stamp,
    required this.nextTurnId,
    this.initialTranscript = '',
  });

  final TurnId nextTurnId;
  final String initialTranscript;
}

final class FalseInterruption extends InteractionEvent {
  const FalseInterruption({required super.stamp});
}

final class AgentFinished extends InteractionEvent {
  const AgentFinished({required super.stamp});
}

final class AgentCancelled extends InteractionEvent {
  const AgentCancelled({required super.stamp});
}

final class SessionClosed extends InteractionEvent {
  const SessionClosed({required super.stamp});
}
