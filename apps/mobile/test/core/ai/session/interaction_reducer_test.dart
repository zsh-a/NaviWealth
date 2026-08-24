import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/contracts/interaction.dart';
import 'package:naviwealth/core/ai/session/delivery_ledger.dart';
import 'package:naviwealth/core/ai/session/interaction_events.dart';
import 'package:naviwealth/core/ai/session/interaction_ids.dart';
import 'package:naviwealth/core/ai/session/interaction_reducer.dart';
import 'package:naviwealth/core/ai/session/interaction_state.dart';

void main() {
  const sessionId = SessionId('session-1');
  const firstTurn = TurnId('turn-1');
  const interruptedTurn = TurnId('turn-2');
  const epochZero = ResponseEpoch.initial();

  InteractionStamp stamp({
    required int sequence,
    TurnId? turnId = firstTurn,
    ResponseEpoch epoch = epochZero,
  }) => InteractionStamp(
    sessionId: sessionId,
    turnId: turnId,
    epoch: epoch,
    sequence: sequence,
  );

  InteractionState apply(InteractionState state, InteractionEvent event) =>
      reduce(state, event);

  test('keeps input, execution, and output lanes independent', () {
    var state = InteractionState.initial(sessionId: sessionId);
    state = apply(
      state,
      TurnStarted(
        stamp: stamp(sequence: 1),
        origin: InteractionInputOrigin.voice,
      ),
    );
    state = apply(state, AgentStarted(stamp: stamp(sequence: 2)));
    state = apply(
      state,
      AgentToolStarted(
        stamp: stamp(sequence: 3),
        operationId: const OperationId('operation-1'),
      ),
    );
    state = apply(state, OutputPlaybackStarted(stamp: stamp(sequence: 4)));
    state = apply(state, SpeechStarted(stamp: stamp(sequence: 5)));

    expect(state.inputLane, InteractionInputLane.speechDetected);
    expect(state.executionLane, InteractionExecutionLane.toolRunning);
    expect(state.outputLane, InteractionOutputLane.playing);
  });

  test(
    'candidate interruption pauses output and false interruption resumes it',
    () {
      var state = InteractionState.initial(sessionId: sessionId);
      state = apply(state, OutputPlaybackStarted(stamp: stamp(sequence: 1)));
      state = apply(
        state,
        BargeInCandidate(
          stamp: stamp(sequence: 2),
          startedAt: DateTime.utc(2026, 8, 24),
        ),
      );

      expect(state.bargeInPhase, BargeInPhase.candidate);
      expect(state.outputLane, InteractionOutputLane.paused);
      expect(state.responseEpoch.value, 0);

      state = apply(state, FalseInterruption(stamp: stamp(sequence: 3)));
      expect(state.bargeInPhase, BargeInPhase.falseInterruption);
      expect(state.responseEpoch.value, 0);

      state = apply(state, OutputPlaybackResumed(stamp: stamp(sequence: 4)));
      expect(state.bargeInPhase, BargeInPhase.none);
      expect(state.outputLane, InteractionOutputLane.playing);
      expect(state.responseEpoch.value, 0);
    },
  );

  test(
    'committed interruption advances epoch and projects delivered prefix only',
    () {
      var state = InteractionState.initial(sessionId: sessionId);
      state = apply(
        state,
        AgentTextGenerated(stamp: stamp(sequence: 1), text: '本月消费 12430 元，'),
      );
      state = apply(
        state,
        OutputSegmentQueued(
          stamp: stamp(sequence: 2),
          segment: const OutputSegment(id: 'segment-1', text: '本月消费 12430 元，'),
        ),
      );
      state = apply(
        state,
        OutputSegmentQueued(
          stamp: stamp(sequence: 3),
          segment: const OutputSegment(id: 'segment-2', text: '其中房租 5200 元。'),
        ),
      );
      state = apply(
        state,
        OutputSegmentDelivered(
          stamp: stamp(sequence: 4),
          segmentId: 'segment-1',
        ),
      );
      state = apply(
        state,
        BargeInCandidate(
          stamp: stamp(sequence: 5),
          startedAt: DateTime.utc(2026, 8, 24),
        ),
      );
      state = apply(
        state,
        BargeInCommitted(
          stamp: stamp(sequence: 6),
          nextTurnId: interruptedTurn,
          initialTranscript: '等等，不算房租。',
        ),
      );

      expect(state.responseEpoch.value, 1);
      expect(state.activeTurnId, interruptedTurn);
      expect(state.outputLane, InteractionOutputLane.interrupted);
      expect(state.generatedText, isEmpty);
      expect(state.deliveryLedger.segments, isEmpty);
      expect(state.transcript, '等等，不算房租。');
      expect(state.lastContextProjection?.deliveredText, '本月消费 12430 元，');
      expect(state.lastContextProjection?.interrupted, isTrue);

      // A late response from epoch 0 can advance ordering but cannot mutate
      // generated text or delivery state in epoch 1.
      state = apply(
        state,
        AgentTextGenerated(
          stamp: stamp(sequence: 7, turnId: firstTurn, epoch: epochZero),
          text: '旧回答不应出现',
        ),
      );
      expect(state.sequence, 7);
      expect(state.generatedText, isEmpty);
    },
  );

  test(
    'pending interaction blocks ordinary input and accepts matching response',
    () {
      var state = InteractionState.initial(sessionId: sessionId);
      final interaction = AiInteractionEnvelope(
        interactionId: 'interaction-1',
        kind: AiInteractionKind.approval,
        mode: AiInteractionMode.oneTap,
        status: AiInteractionStatus.pending,
        title: '确认操作',
        createdAt: DateTime.utc(2026, 8, 24),
        resumeKind: AiInteractionResumeKind.chatTurn,
      );
      state = apply(
        state,
        AgentWaitingForInteraction(
          stamp: stamp(sequence: 1),
          interaction: interaction,
        ),
      );

      state = apply(
        state,
        InputCommitted(
          stamp: stamp(sequence: 2),
          text: '看看这个月消费',
          origin: InteractionInputOrigin.voice,
        ),
      );
      expect(state.pendingInteraction, same(interaction));
      expect(state.lastCommittedText, isNull);

      final response = AiInteractionResponse(
        interactionId: interaction.interactionId,
        action: AiInteractionAction.approve,
        value: true,
        respondedAt: DateTime.utc(2026, 8, 24),
        respondedBy: 'voice',
      );
      state = apply(
        state,
        InputCommitted(
          stamp: stamp(sequence: 3),
          text: '确认',
          origin: InteractionInputOrigin.voice,
          interactionResponse: response,
        ),
      );

      expect(state.pendingInteraction, isNull);
      expect(state.executionLane, InteractionExecutionLane.running);
      expect(state.lastInteractionResponse, same(response));
    },
  );

  test('delivery ledger ignores unknown segments and preserves order', () {
    var ledger = DeliveryLedger.empty();
    ledger = ledger.queue(const OutputSegment(id: 'a', text: '第一段'));
    ledger = ledger.queue(const OutputSegment(id: 'b', text: '第二段'));
    ledger = ledger.markDelivered('unknown');
    expect(ledger.deliveredText, isEmpty);
    ledger = ledger.markDelivered('b');
    expect(ledger.deliveredText, '第二段');
    ledger = ledger.markDelivered('a');
    expect(ledger.deliveredText, '第一段第二段');
  });
}
