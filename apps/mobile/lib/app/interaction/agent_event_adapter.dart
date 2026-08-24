import '../../core/ai/contracts/chat_events.dart';
import '../../core/ai/contracts/interaction.dart';
import '../../core/ai/session/delivery_ledger.dart';
import '../../core/ai/session/interaction_events.dart';
import '../../core/ai/session/interaction_ids.dart';
import '../../core/ai/session/output_text_segmenter.dart';
import 'interaction_session_coordinator.dart';

typedef OutputSegmentSink = void Function(OutputSegment segment);

/// Maps the existing provider-neutral Chat event vocabulary into the
/// InteractionSession lanes.
///
/// The adapter does not run tools, persist messages, or infer business state.
/// `ChatRepository`/Agent Runtime remain the semantic and durable owners;
/// this class only projects their events into timing, delivery, and
/// interruption state.
final class AgentEventAdapter {
  AgentEventAdapter(
    this._coordinator, {
    OutputTextSegmenter? segmenter,
    this.onOutputSegment,
  }) : _segmenter = segmenter ?? OutputTextSegmenter();

  final InteractionSessionCoordinator _coordinator;
  final OutputTextSegmenter _segmenter;
  final OutputSegmentSink? onOutputSegment;

  /// Projects a whole provider stream through the same ordered adapter.
  Future<void> acceptStream(
    Stream<AiChatEvent> events, {
    required TurnId turnId,
    required ResponseEpoch epoch,
  }) async {
    await for (final event in events) {
      accept(event, turnId: turnId, epoch: epoch);
    }
  }

  void accept(
    AiChatEvent event, {
    required TurnId turnId,
    required ResponseEpoch epoch,
  }) {
    switch (event) {
      case ToolCallStartEvent(:final id):
        _coordinator.dispatch(
          (stamp) =>
              AgentToolStarted(stamp: stamp, operationId: OperationId(id)),
          turnId: turnId,
          epoch: epoch,
          operationId: OperationId(id),
        );
      case ToolCallEvent(:final id):
        _coordinator.dispatch(
          (stamp) =>
              AgentToolStarted(stamp: stamp, operationId: OperationId(id)),
          turnId: turnId,
          epoch: epoch,
          operationId: OperationId(id),
        );
      case ToolResultEvent(:final id, :final output):
        _coordinator.dispatch(
          (stamp) =>
              AgentToolFinished(stamp: stamp, operationId: OperationId(id)),
          turnId: turnId,
          epoch: epoch,
          operationId: OperationId(id),
        );
        final interaction = _pendingInteraction(output);
        if (interaction != null) {
          _coordinator.dispatch(
            (stamp) => AgentWaitingForInteraction(
              stamp: stamp,
              interaction: interaction,
            ),
            turnId: turnId,
            epoch: epoch,
          );
        }
      case TextEvent(:final text):
        _coordinator.dispatch(
          (stamp) => AgentTextGenerated(stamp: stamp, text: text),
          turnId: turnId,
          epoch: epoch,
        );
        if (_isCurrent(epoch)) {
          _queueSegments(_segmenter.add(text, epoch: epoch));
        }
      case DoneEvent():
        _coordinator.dispatch(
          (stamp) => AgentFinished(stamp: stamp),
          turnId: turnId,
          epoch: epoch,
        );
        if (_isCurrent(epoch)) {
          _queueSegments(_segmenter.flush(epoch: epoch));
        }
      case ErrorEvent(:final code):
        _coordinator.dispatch(
          (stamp) => AgentFailed(stamp: stamp, code: code),
          turnId: turnId,
          epoch: epoch,
        );
      case ToolCallDeltaEvent() ||
          ThinkingDeltaEvent() ||
          UsageEvent() ||
          ProgressEvent() ||
          SpanEvent():
        // These events remain owned by the chat/trace surfaces. They do not
        // change session execution or delivery state.
        break;
    }
  }

  bool _isCurrent(ResponseEpoch epoch) =>
      _coordinator.state.responseEpoch == epoch;

  void _queueSegments(List<OutputSegment> segments) {
    for (final segment in segments) {
      _coordinator.queueOutputSegment(segment);
      onOutputSegment?.call(segment);
    }
  }

  static AiInteractionEnvelope? _pendingInteraction(Object? output) {
    if (output is! Map) return null;
    final map = output.map((key, value) => MapEntry('$key', value));
    final interaction = AiInteractionEnvelope.tryParse(map['interaction']);
    if (interaction == null ||
        interaction.status != AiInteractionStatus.pending ||
        interaction.resumeKind != AiInteractionResumeKind.chatTurn) {
      return null;
    }
    return interaction;
  }
}
