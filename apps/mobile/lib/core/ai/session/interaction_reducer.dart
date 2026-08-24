import 'delivery_ledger.dart';
import 'interaction_events.dart';
import 'interaction_state.dart';

/// Applies one ordered event to an InteractionSession state.
///
/// The reducer is deliberately pure. It does not cancel futures, access
/// microphone/audio APIs, call the Agent Runtime, or apply domain writes. A
/// host Coordinator performs those side effects after dispatching the event.
InteractionState reduce(InteractionState state, InteractionEvent event) {
  if (state.isClosed || event.stamp.sessionId != state.sessionId) return state;
  if (event.stamp.sequence <= state.sequence) return state;

  // Consume the global ordering number even when an event is stale for the
  // current response epoch. This preserves the Coordinator's total order.
  final ordered = state.copyWith(sequence: event.stamp.sequence);
  if (event.stamp.epoch != state.responseEpoch && event is! SessionClosed) {
    return ordered;
  }

  return switch (event) {
    TurnStarted() => _turnStarted(ordered, event),
    SpeechStarted() => ordered.copyWith(
      inputLane: InteractionInputLane.speechDetected,
    ),
    SpeechStopped() => ordered.copyWith(
      inputLane: InteractionInputLane.endpointing,
    ),
    TranscriptUpdated() => ordered.copyWith(
      transcript: event.text,
      inputLane: event.isFinal
          ? InteractionInputLane.endpointing
          : InteractionInputLane.speechDetected,
    ),
    InputCommitted() => _inputCommitted(ordered, event),
    AgentStarted() => ordered.copyWith(
      executionLane: InteractionExecutionLane.running,
      executingTurnId: event.stamp.turnId,
      activeOperationId: null,
    ),
    AgentToolStarted() => ordered.copyWith(
      executionLane: InteractionExecutionLane.toolRunning,
      executingTurnId: event.stamp.turnId,
      activeOperationId: event.operationId,
    ),
    AgentWaitingForInteraction() => ordered.copyWith(
      executionLane: InteractionExecutionLane.waitingInteraction,
      pendingInteraction: event.interaction,
      activeOperationId: null,
    ),
    AgentTextGenerated() => ordered.copyWith(
      generatedText: '${ordered.generatedText}${event.text}',
      outputLane: ordered.outputLane == InteractionOutputLane.idle
          ? InteractionOutputLane.synthesizing
          : ordered.outputLane,
    ),
    OutputSegmentQueued() => ordered.copyWith(
      deliveryLedger: ordered.deliveryLedger.queue(event.segment),
      outputLane: ordered.outputLane == InteractionOutputLane.idle
          ? InteractionOutputLane.synthesizing
          : ordered.outputLane,
    ),
    OutputPlaybackStarted() => ordered.copyWith(
      outputLane: InteractionOutputLane.playing,
    ),
    OutputSegmentDelivered() => ordered.copyWith(
      deliveryLedger: ordered.deliveryLedger.markDelivered(event.segmentId),
      outputLane: ordered.outputLane == InteractionOutputLane.paused
          ? InteractionOutputLane.paused
          : InteractionOutputLane.playing,
    ),
    OutputPlaybackPaused() => ordered.copyWith(
      outputLane: InteractionOutputLane.paused,
    ),
    OutputPlaybackResumed() => ordered.copyWith(
      outputLane: InteractionOutputLane.playing,
      bargeInPhase: BargeInPhase.none,
      candidateStartedAt: null,
    ),
    OutputPlaybackStopped() => ordered.copyWith(
      outputLane: event.interrupted
          ? InteractionOutputLane.interrupted
          : InteractionOutputLane.idle,
      lastContextProjection: ordered.deliveryLedger.project(
        epoch: ordered.responseEpoch,
        interrupted: event.interrupted,
      ),
    ),
    BargeInCandidate() => ordered.copyWith(
      bargeInPhase: BargeInPhase.candidate,
      candidateStartedAt: event.startedAt,
      outputLane: _pauseOutput(ordered.outputLane),
    ),
    BargeInCommitted() => _bargeInCommitted(ordered, event),
    FalseInterruption() => ordered.copyWith(
      bargeInPhase: BargeInPhase.falseInterruption,
      candidateStartedAt: null,
    ),
    AgentFinished() => _agentFinished(ordered, event),
    AgentCancelled() => _agentCancelled(ordered, event),
    SessionClosed() => ordered.copyWith(
      status: InteractionSessionStatus.closed,
      inputLane: InteractionInputLane.idle,
      executionLane: InteractionExecutionLane.idle,
      outputLane: InteractionOutputLane.idle,
      activeOperationId: null,
      pendingInteraction: null,
    ),
  };
}

InteractionState _turnStarted(InteractionState state, TurnStarted event) =>
    state.copyWith(
      activeTurnId: event.stamp.turnId,
      inputOrigin: event.origin,
      inputLane: event.origin == InteractionInputOrigin.voice
          ? InteractionInputLane.listening
          : InteractionInputLane.committed,
      transcript: '',
      generatedText: '',
      deliveryLedger: DeliveryLedger.empty(),
      bargeInPhase: BargeInPhase.none,
      candidateStartedAt: null,
      lastCommittedText: null,
      lastCommittedOrigin: null,
      lastInteractionResponse: null,
    );

InteractionState _inputCommitted(InteractionState state, InputCommitted event) {
  final pending = state.pendingInteraction;
  if (pending != null) {
    final response = event.interactionResponse;
    if (response == null || response.interactionId != pending.interactionId) {
      // A pending HITL envelope has priority. Do not let voice text become a
      // new ordinary turn or bypass approval/typed confirmation.
      return state;
    }
    return state.copyWith(
      inputLane: InteractionInputLane.committed,
      inputOrigin: event.origin,
      activeTurnId: event.stamp.turnId,
      transcript: event.text,
      lastCommittedText: event.text,
      lastCommittedOrigin: event.origin,
      lastInteractionResponse: response,
      pendingInteraction: null,
      executionLane: InteractionExecutionLane.running,
    );
  }
  return state.copyWith(
    inputLane: InteractionInputLane.committed,
    inputOrigin: event.origin,
    activeTurnId: event.stamp.turnId,
    transcript: event.text,
    lastCommittedText: event.text,
    lastCommittedOrigin: event.origin,
    lastInteractionResponse: event.interactionResponse,
  );
}

InteractionState _bargeInCommitted(
  InteractionState state,
  BargeInCommitted event,
) => state.copyWith(
  responseEpoch: state.responseEpoch.next(),
  activeTurnId: event.nextTurnId,
  inputOrigin: InteractionInputOrigin.voice,
  inputLane: InteractionInputLane.speechDetected,
  transcript: event.initialTranscript,
  generatedText: '',
  deliveryLedger: DeliveryLedger.empty(),
  bargeInPhase: BargeInPhase.committed,
  candidateStartedAt: null,
  outputLane: InteractionOutputLane.interrupted,
  lastContextProjection: state.deliveryLedger.project(
    epoch: state.responseEpoch,
    interrupted: true,
  ),
);

InteractionState _agentFinished(InteractionState state, AgentFinished event) {
  if (state.executingTurnId != null &&
      state.executingTurnId != event.stamp.turnId) {
    return state;
  }
  return state.copyWith(
    executionLane: InteractionExecutionLane.done,
    activeOperationId: null,
  );
}

InteractionState _agentCancelled(InteractionState state, AgentCancelled event) {
  if (state.executingTurnId != null &&
      state.executingTurnId != event.stamp.turnId) {
    return state;
  }
  return state.copyWith(
    executionLane: InteractionExecutionLane.idle,
    activeOperationId: null,
  );
}

InteractionOutputLane _pauseOutput(InteractionOutputLane lane) =>
    switch (lane) {
      InteractionOutputLane.synthesizing ||
      InteractionOutputLane.playing => InteractionOutputLane.paused,
      _ => lane,
    };
