import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/app/interaction/interaction_session_coordinator.dart';
import 'package:naviwealth/core/ai/contracts/interaction.dart';
import 'package:naviwealth/core/ai/session/delivery_ledger.dart';
import 'package:naviwealth/core/ai/session/interaction_events.dart';
import 'package:naviwealth/core/ai/session/interaction_ids.dart';
import 'package:naviwealth/core/ai/session/interaction_state.dart';

void main() {
  test(
    'Coordinator assigns one global sequence and commits valid barge-in',
    () async {
      ResponseEpoch? staleEpoch;
      final coordinator = InteractionSessionCoordinator(
        sessionId: const SessionId('session-1'),
        onEpochAdvanced: (epoch) => staleEpoch = epoch,
        clock: () => DateTime.utc(2026, 8, 24),
      );

      coordinator.startTurn(InteractionInputOrigin.voice);
      coordinator.agentTextGenerated('本月消费 12430 元。');
      coordinator.queueOutputSegment(
        const OutputSegment(id: 'segment-1', text: '本月消费 12430 元。'),
      );
      coordinator.outputPlaybackStarted();
      final beforeCandidate = coordinator.state.sequence;

      coordinator.speechStarted();
      expect(coordinator.state.outputLane, InteractionOutputLane.paused);
      expect(coordinator.state.bargeInPhase, BargeInPhase.candidate);

      coordinator.updateTranscript('等等，不算房租。', isFinal: false);

      expect(coordinator.state.responseEpoch.value, 1);
      expect(coordinator.state.transcript, '等等，不算房租。');
      expect(coordinator.state.sequence, greaterThan(beforeCandidate));
      expect(staleEpoch?.value, 0);

      // Explicitly replay a late old-epoch event through the Coordinator seam.
      coordinator.dispatch(
        (stamp) => AgentTextGenerated(stamp: stamp, text: 'stale'),
        epoch: const ResponseEpoch.initial(),
      );
      expect(coordinator.state.generatedText, isEmpty);

      await coordinator.close();
    },
  );

  test(
    'typed HITL voice text does not bypass the on-screen confirmation path',
    () async {
      final requests = <InteractionTurnRequest>[];
      final coordinator = InteractionSessionCoordinator(
        sessionId: const SessionId('session-1'),
        onTurnCommitted: (request) async => requests.add(request),
      );
      coordinator.startTurn(InteractionInputOrigin.voice);
      coordinator.agentWaitingForInteraction(
        AiInteractionEnvelope(
          interactionId: 'typed-1',
          kind: AiInteractionKind.approval,
          mode: AiInteractionMode.typed,
          status: AiInteractionStatus.pending,
          title: '输入确认文本',
          createdAt: DateTime.utc(2026, 8, 24),
          resumeKind: AiInteractionResumeKind.chatTurn,
          confirmation: const AiInteractionConfirmation(requiredText: '执行'),
        ),
      );

      coordinator.commitInput('执行');
      await Future<void>.delayed(Duration.zero);

      expect(coordinator.state.pendingInteraction, isNotNull);
      expect(requests, isEmpty);
      await coordinator.close();
    },
  );
}
