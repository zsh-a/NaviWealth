import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/app/interaction/agent_event_adapter.dart';
import 'package:naviwealth/app/interaction/interaction_session_coordinator.dart';
import 'package:naviwealth/core/ai/contracts/chat_events.dart';
import 'package:naviwealth/core/ai/contracts/interaction.dart';
import 'package:naviwealth/core/ai/session/interaction_ids.dart';
import 'package:naviwealth/core/ai/session/interaction_state.dart';

void main() {
  test('projects tool lifecycle and pending HITL into session state', () async {
    final coordinator = InteractionSessionCoordinator(
      sessionId: const SessionId('session-1'),
    );
    final turnId = coordinator.startTurn(InteractionInputOrigin.voice);
    coordinator.agentStarted();
    final adapter = AgentEventAdapter(coordinator);

    adapter.accept(
      const ToolCallStartEvent(id: 'tool-1', name: 'read_expenses'),
      turnId: turnId,
      epoch: const ResponseEpoch.initial(),
    );
    expect(
      coordinator.state.executionLane,
      InteractionExecutionLane.toolRunning,
    );
    expect(coordinator.state.activeOperationId?.value, 'tool-1');

    final interaction = AiInteractionEnvelope(
      interactionId: 'interaction-1',
      kind: AiInteractionKind.approval,
      mode: AiInteractionMode.oneTap,
      status: AiInteractionStatus.pending,
      title: '确认',
      createdAt: DateTime.utc(2026, 8, 24),
      resumeKind: AiInteractionResumeKind.chatTurn,
    );
    adapter.accept(
      ToolResultEvent(
        id: 'tool-1',
        name: 'read_expenses',
        output: <String, Object?>{'interaction': interaction.toJson()},
      ),
      turnId: turnId,
      epoch: const ResponseEpoch.initial(),
    );

    expect(
      coordinator.state.executionLane,
      InteractionExecutionLane.waitingInteraction,
    );
    expect(
      coordinator.state.pendingInteraction?.interactionId,
      'interaction-1',
    );

    adapter.accept(
      const DoneEvent(stopReason: 'end_turn', rounds: 1),
      turnId: turnId,
      epoch: const ResponseEpoch.initial(),
    );
    expect(
      coordinator.state.executionLane,
      InteractionExecutionLane.waitingInteraction,
    );

    await coordinator.close();
  });

  test(
    'late Chat events from an old epoch cannot mutate generated text',
    () async {
      final coordinator = InteractionSessionCoordinator(
        sessionId: const SessionId('session-1'),
      );
      final turnId = coordinator.startTurn(InteractionInputOrigin.voice);
      final adapter = AgentEventAdapter(coordinator);
      const epoch = ResponseEpoch.initial();

      adapter.accept(const TextEvent('当前回答'), turnId: turnId, epoch: epoch);
      coordinator.outputPlaybackStarted();
      coordinator.speechStarted();
      coordinator.updateTranscript('等等', isFinal: false);
      expect(coordinator.state.responseEpoch.value, 1);
      expect(coordinator.state.generatedText, isEmpty);

      adapter.accept(const TextEvent('旧回答'), turnId: turnId, epoch: epoch);
      expect(coordinator.state.generatedText, isEmpty);

      await coordinator.close();
    },
  );
}
