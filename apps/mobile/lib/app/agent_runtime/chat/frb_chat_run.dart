part of 'frb_chat_runner.dart';

/// Coordinates native rounds and host effects. Rust owns provider execution,
/// round budgets and continuation semantics; this host only relays resumes.
final class _FrbChatRun {
  const _FrbChatRun({
    required this.streamBridge,
    required this.tools,
    required this.toolLineHandler,
    required this.snapshotStore,
    required this.maxToolRounds,
    required this.agentId,
    required this.emitModelProgress,
  });
  final AgentRuntimeLlmStreamBridge streamBridge;
  final List<Map<String, Object?>> tools;
  final AgentRuntimeToolLineHandler? toolLineHandler;
  final AgentRuntimeChatSnapshotStore? snapshotStore;
  final int maxToolRounds;
  final String agentId;
  final bool emitModelProgress;

  Stream<AiChatEvent> run(ChatAgentTurnRequest request) async* {
    final initialMessages = [
      for (final message in request.messages) message.toJson(),
    ];
    final contextBlocks = [
      for (final block in request.contextBlocks) block.toJson(),
    ];
    final journal = _FrbChatToolJournal(
      store: snapshotStore,
      turnId: request.turnId,
      tools: tools,
      toolLineHandler: toolLineHandler,
      cancelToken: request.cancelToken,
    );
    var roundsUsed = 0;
    Map<String, Object?>? chatState;
    var toolResults = const <Map<String, Object?>>[];
    var interactionResponse = request.interactionResponse?.toJson();
    Map<String, Object?>? suspendInteraction;
    final recovery = await journal.recover();
    if (recovery != null) {
      roundsUsed = recovery.round;
      for (final event in recovery.events) {
        yield event;
      }
      switch (recovery) {
        case _ChatRecoveryCancelled():
          yield DoneEvent(stopReason: 'error', rounds: recovery.round);
          return;
        case _ChatRecoveryFailed(:final code, :final message):
          yield ErrorEvent(message, code: code);
          yield DoneEvent(stopReason: 'error', rounds: recovery.round);
          return;
        case _ChatRecoveryAwaitingInteraction():
          if (interactionResponse == null) {
            yield DoneEvent(
              stopReason: 'requires_interaction',
              rounds: recovery.round,
            );
            return;
          }
          chatState = recovery.chatState;
        case _ChatRecoveryToolResults():
          chatState = recovery.chatState;
          toolResults = recovery.toolResults;
        case _ChatRecoverySuspendInteraction(:final interaction):
          chatState = recovery.chatState;
          toolResults = recovery.toolResults;
          suspendInteraction = interaction;
      }
    }
    if (interactionResponse != null && chatState == null) {
      yield const ErrorEvent(
        'FRB chat interaction response has no resumable snapshot',
        code: 'frb_chat_interaction_snapshot_missing',
      );
      yield const DoneEvent(stopReason: 'error', rounds: 0);
      return;
    }
    while (true) {
      final nextRound = roundsUsed + 1;
      final roundId = 'r$nextRound';
      final roundStart = DateTime.now().toUtc();
      if (emitModelProgress) {
        yield ProgressEvent(
          LongTaskProgress(id: roundId, label: 'model', startedAt: roundStart),
        );
      }
      final projector = _FrbChatEventProjector(
        initialRound: nextRound,
        roundStart: roundStart,
        model: request.model,
        cancelToken: request.cancelToken,
        tools: tools,
        inputMessageCount: initialMessages.length,
        traceInput: frbClip(
          jsonEncode({
            'initial_messages': initialMessages,
            'tool_results': toolResults,
            'context_blocks': contextBlocks,
          }),
          8000,
        ),
      );
      final stream = streamBridge.streamChatTurn(
        messages: initialMessages,
        tools: tools,
        contextBlocks: contextBlocks,
        contextPolicy: request.contextPolicy?.toJson(),
        temperature: request.temperature,
        maxOutputTokens: request.maxOutputTokens,
        metadata: <String, Object?>{
          ...request.metadata,
          'turn_id': ?request.turnId,
          'session_id': ?request.sessionId,
          'thread_id': ?request.threadId,
          'agent_id': request.agentId ?? agentId,
          'surface': request.surface ?? 'ai_chat',
          'mode': ?request.mode,
          'requested_model': ?request.model,
          'streaming': true,
          'round': nextRound,
        },
        maxToolRounds: maxToolRounds,
        turnId: request.turnId,
        sessionId: request.sessionId,
        threadId: request.threadId,
        surface: request.surface ?? 'ai_chat',
        agentId: request.agentId ?? agentId,
        mode: request.mode,
        chatState: chatState,
        toolResults: toolResults,
        interactionResponse: interactionResponse,
        suspendInteraction: suspendInteraction,
      );
      toolResults = const <Map<String, Object?>>[];
      interactionResponse = null;
      suspendInteraction = null;
      yield* projector.project(
        _cancelableFrbStream(stream, request.cancelToken),
      );
      final projection = projector.result;
      if (projection is _FrbRoundStopped) return;
      final ready = projection as _FrbRoundReady;
      final state = ready.state;
      roundsUsed = ready.round;
      if (ready.status == 'requires_interaction') {
        final pending = state.chatState;
        if (pending == null) {
          yield const ErrorEvent(
            'FRB chat requires interaction but did not return chat_state',
            code: 'frb_chat_interaction_state_missing',
          );
          yield DoneEvent(stopReason: 'error', rounds: roundsUsed);
          return;
        }
        await journal.save(
          state.chatSnapshot ??
              _buildPendingInteractionSnapshot(state: pending),
        );
        yield DoneEvent(stopReason: 'requires_interaction', rounds: roundsUsed);
        return;
      }
      if (ready.status != 'requires_tool_results') {
        final terminal = state.chatState;
        if (terminal != null) {
          await journal.save(
            state.chatSnapshot ??
                _buildTerminalChatSnapshot(
                  state: terminal,
                  status: 'completed',
                  stopReason: state.doneStopReason ?? state.stopReason,
                ),
          );
        }
        yield DoneEvent(
          stopReason: state.doneStopReason ?? state.stopReason,
          rounds: roundsUsed,
        );
        return;
      }
      chatState = state.chatState;
      if (chatState == null) {
        yield const ErrorEvent(
          'FRB chat requires tool results but did not return chat_state',
          code: 'frb_chat_state_missing',
        );
        yield DoneEvent(stopReason: 'error', rounds: roundsUsed);
        return;
      }
      await journal.save(
        state.chatSnapshot ??
            _buildPendingChatSnapshot(
              state: chatState,
              calls: state.requiredToolCalls,
              tools: tools,
            ),
      );
      final batch = _FrbChatToolBatch(
        journal: journal,
        round: roundsUsed,
        roundId: roundId,
      );
      yield* batch.dispatch(state.requiredToolCalls);
      switch (batch.result) {
        case _ChatToolBatchCancelled():
          yield DoneEvent(stopReason: 'error', rounds: roundsUsed);
          return;
        case _ChatToolBatchFailed(:final code, :final message):
          if (code == _kInteractionEnvelopeErrorCode) {
            yield frbLlmSpan(
              round: roundsUsed,
              roundId: roundId,
              startedAt: roundStart,
              state: state,
              requestedModel: request.model,
              status: AiSpanStatus.error,
              errorCode: code,
              errorMessage: message,
            );
          }
          yield ErrorEvent(message, code: code);
          yield DoneEvent(stopReason: 'error', rounds: roundsUsed);
          return;
        case _ChatToolBatchReady(:final results):
          toolResults = results;
        case _ChatToolBatchSuspend(:final results, :final interaction):
          toolResults = results;
          suspendInteraction = interaction;
      }
    }
  }
}
