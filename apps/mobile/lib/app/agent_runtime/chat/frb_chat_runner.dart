/// FRB-backed adapter for the existing AI Chat runner seam.
///
/// The native FRB LLM API now exposes a primitive JSON event stream. This runner
/// maps those native events into the existing `AiChatEvent` vocabulary. Tool
/// calls are executed through the JSON-RPC tool host and fed back into bounded
/// follow-up LLM rounds, matching the existing device loop contract.
library;

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:naviwealth/app/agent_runtime/bridges/agent_runtime_llm_stream_bridge.dart';
import 'package:naviwealth/app/agent_runtime/chat/frb_chat_event.dart';
import 'package:naviwealth/app/agent_runtime/chat/frb_chat_trace_mapper.dart';
import 'package:naviwealth/app/agent_runtime/chat/frb_chat_types.dart';
import 'package:naviwealth/app/agent_runtime/persistence/agent_runtime_chat_snapshot_store.dart';
import 'package:naviwealth/app/agent_runtime/tools/agent_runtime_tool_dispatcher.dart';
import 'package:naviwealth/core/ai/contracts/contracts.dart';
import 'package:naviwealth/core/ai/progress/long_task_progress.dart';
import 'package:naviwealth/core/ai/runtime/ai_runtime.dart';
import 'package:naviwealth/core/ai/runtime/device/device_system_prompt.dart'
    show kMaxToolRounds;
import 'package:naviwealth/core/ai/runtime/device/tools/ask_user_tool.dart'
    show kAskUserToolName;

const String kFrbChatRunnerAgentId = 'ai_chat';
const String _kInteractionEnvelopeErrorCode =
    'frb_chat_interaction_envelope_invalid';
const String _kInteractionEnvelopeErrorMessage =
    'ask_user tool result must include a valid pending chat interaction envelope';
const String _kToolNotAllowedErrorCode = 'frb_chat_tool_not_allowed';
const String _kAskUserBatchErrorCode = 'frb_chat_ask_user_not_exclusive';
const String _kTerminalDoneMissingErrorCode = 'frb_chat_terminal_done_missing';
const String _kToolCancelledErrorCode = 'cancelled';
const String _kToolCancelledMessage = 'FRB chat tool dispatch cancelled';

class FrbChatRunner implements ChatAgent {
  FrbChatRunner({
    required AgentRuntimeLlmStreamBridge streamBridge,
    List<Map<String, Object?>> tools = const <Map<String, Object?>>[],
    AgentRuntimeToolLineHandler? toolLineHandler,
    AgentRuntimeChatSnapshotStore? snapshotStore,
    int maxToolRounds = kMaxToolRounds,
    String agentId = kFrbChatRunnerAgentId,
  }) : _streamBridge = streamBridge,
       _toolsReader = (() => tools),
       _toolLineHandler = toolLineHandler,
       _snapshotStore = snapshotStore,
       _maxToolRounds = maxToolRounds,
       _agentId = agentId;

  const FrbChatRunner.lazyTools({
    required AgentRuntimeLlmStreamBridge streamBridge,
    required List<Map<String, Object?>> Function() toolsReader,
    AgentRuntimeToolLineHandler? toolLineHandler,
    AgentRuntimeChatSnapshotStore? snapshotStore,
    int maxToolRounds = kMaxToolRounds,
    String agentId = kFrbChatRunnerAgentId,
  }) : _streamBridge = streamBridge,
       _toolsReader = toolsReader,
       _toolLineHandler = toolLineHandler,
       _snapshotStore = snapshotStore,
       _maxToolRounds = maxToolRounds,
       _agentId = agentId;

  final AgentRuntimeLlmStreamBridge _streamBridge;
  final List<Map<String, Object?>> Function() _toolsReader;
  final AgentRuntimeToolLineHandler? _toolLineHandler;
  final AgentRuntimeChatSnapshotStore? _snapshotStore;
  final int _maxToolRounds;
  final String _agentId;

  @override
  Stream<AiChatEvent> runTurn(ChatAgentTurnRequest request) {
    return _runRequest(request);
  }

  Stream<AiChatEvent> run({
    required List<ChatAgentMessage> messages,
    Map<String, Object?>? portfolioSnapshot,
    ContextPack? contextPack,
    String? model,
    double? temperature,
    int? maxOutputTokens,
    CancelToken? cancelToken,
  }) {
    return _runRequest(
      ChatAgentTurnRequest(
        messages: messages,
        surface: 'ai_chat',
        agentId: _agentId,
        mode: 'chat',
        portfolioSnapshot: portfolioSnapshot,
        contextPack: contextPack,
        model: model,
        temperature: temperature,
        maxOutputTokens: maxOutputTokens,
        cancelToken: cancelToken,
      ),
    );
  }

  Stream<AiChatEvent> _runRequest(ChatAgentTurnRequest request) async* {
    final cancelToken = request.cancelToken;
    if (cancelToken?.isCancelled == true) {
      yield const DoneEvent(stopReason: 'error', rounds: 0);
      return;
    }

    try {
      yield* _runStream(streamBridge: _streamBridge, request: request);
    } catch (error) {
      yield ErrorEvent(error.toString(), code: 'frb_chat_error');
      yield const DoneEvent(stopReason: 'error', rounds: 1);
    }
  }

  Stream<AiChatEvent> _runStream({
    required AgentRuntimeLlmStreamBridge streamBridge,
    required ChatAgentTurnRequest request,
  }) async* {
    final messages = request.messages;
    final model = request.model;
    final cancelToken = request.cancelToken;
    final initialMessages = <Map<String, Object?>>[
      for (final message in messages) message.toJson(),
    ];
    final tools = _toolsReader();
    final contextBlocks = _contextBlocksFor(request);
    var roundsUsed = 0;
    Map<String, Object?>? chatState;
    var toolResults = const <Map<String, Object?>>[];
    var interactionResponse = request.interactionResponse?.toJson();
    Map<String, Object?>? suspendInteraction;
    AgentRuntimeChatSnapshotRecord? snapshotRecord;
    final snapshotStore = _snapshotStore;
    final turnId = request.turnId;
    if (snapshotStore != null && turnId != null && turnId.isNotEmpty) {
      snapshotRecord = await snapshotStore.loadResumable(turnId);
      if (snapshotRecord case final record?) {
        final recovery = await _recoverChatSnapshot(
          record: record,
          store: snapshotStore,
          toolLineHandler: _toolLineHandler,
          allowedToolNames: _toolNames(tools),
          cancelToken: cancelToken,
        );
        snapshotRecord = recovery.record;
        for (final event in recovery.events) {
          yield event;
        }
        if (recovery.cancelled) {
          yield DoneEvent(stopReason: 'error', rounds: recovery.round);
          return;
        }
        if (recovery.errorCode case final code?) {
          yield ErrorEvent(recovery.errorMessage!, code: code);
          yield DoneEvent(stopReason: 'error', rounds: recovery.round);
          return;
        }
        chatState = recovery.chatState;
        toolResults = recovery.toolResults;
        roundsUsed = recovery.round;
        suspendInteraction = recovery.suspendInteraction;
        if (record.status == 'requires_interaction' &&
            recovery.awaitingUser &&
            interactionResponse == null) {
          yield DoneEvent(
            stopReason: 'requires_interaction',
            rounds: recovery.round,
          );
          return;
        }
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
      roundsUsed = nextRound;
      final roundId = 'r$nextRound';
      final roundStart = DateTime.now().toUtc();
      final state = FrbStreamRoundState(
        inputMessageCount: initialMessages.length,
      );
      var finished = false;
      final stream = _cancelableFrbStream(
        streamBridge.streamChatTurn(
          messages: initialMessages,
          tools: tools,
          contextBlocks: [for (final block in contextBlocks) block.toJson()],
          contextPolicy: request.contextPolicy?.toJson(),
          temperature: request.temperature,
          maxOutputTokens: request.maxOutputTokens,
          metadata: <String, Object?>{
            ...request.metadata,
            'turn_id': ?request.turnId,
            'session_id': ?request.sessionId,
            'thread_id': ?request.threadId,
            'agent_id': request.agentId ?? _agentId,
            'surface': request.surface ?? 'ai_chat',
            'mode': ?request.mode,
            'requested_model': ?model,
            'portfolio_snapshot': ?request.portfolioSnapshot,
            'context_pack': ?request.contextPack?.toJson(),
            'streaming': true,
            'round': nextRound,
          },
          maxToolRounds: _maxToolRounds,
          turnId: request.turnId,
          sessionId: request.sessionId,
          threadId: request.threadId,
          surface: request.surface ?? 'ai_chat',
          agentId: request.agentId ?? _agentId,
          mode: request.mode,
          chatState: chatState,
          toolResults: toolResults,
          interactionResponse: interactionResponse,
          suspendInteraction: suspendInteraction,
        ),
        cancelToken,
      );
      toolResults = const <Map<String, Object?>>[];
      interactionResponse = null;
      suspendInteraction = null;
      var doneReceived = false;
      await for (final rawEvent in stream) {
        final event = FrbChatStreamEvent.parse(rawEvent);
        final eventRound = event.round;
        if (eventRound > 0) roundsUsed = eventRound;
        if (cancelToken?.isCancelled == true) {
          yield frbLlmSpan(
            round: roundsUsed == 0 ? nextRound : roundsUsed,
            roundId: roundId,
            startedAt: roundStart,
            state: state,
            requestedModel: model,
            status: AiSpanStatus.cancelled,
            errorCode: 'cancelled',
            errorMessage: 'FRB chat stream cancelled',
          );
          yield DoneEvent(stopReason: 'error', rounds: roundsUsed);
          return;
        }
        switch (event) {
          case FrbChatCancelledEvent():
            yield frbLlmSpan(
              round: roundsUsed == 0 ? nextRound : roundsUsed,
              roundId: roundId,
              startedAt: roundStart,
              state: state,
              requestedModel: model,
              status: AiSpanStatus.cancelled,
              errorCode: 'cancelled',
              errorMessage: 'FRB chat stream cancelled',
            );
            yield DoneEvent(stopReason: 'error', rounds: roundsUsed);
            return;
          case FrbChatStartedEvent():
          case FrbChatLlmStartedEvent():
            break;
          case FrbChatUsageEvent(:final usage):
            state.recordUsage(usage);
            yield UsageEvent(usage);
          case FrbChatDoneEvent(:final metadata):
            doneReceived = true;
            state.finishDone(metadata);
            break;
          case FrbChatDeltaEvent(:final content):
            if (content.isNotEmpty) {
              state.appendText(content);
              yield TextEvent(content);
            }
          case FrbChatThinkingDeltaEvent(:final content):
            if (content.isNotEmpty) {
              state.appendThinking(content);
              yield ThinkingDeltaEvent(content);
            }
          case FrbChatThinkingSignatureDeltaEvent(:final content):
            state.appendThinkingSignature(content);
          case FrbChatToolCallStartEvent(:final id, :final name):
            state.startToolCall(id: id, name: name);
            yield ToolCallStartEvent(id: id, name: name);
          case FrbChatToolCallDeltaEvent(:final id, :final partialInputJson):
            state.appendToolInput(id: id, partialInputJson: partialInputJson);
            yield ToolCallDeltaEvent(
              id: id,
              partialInputJson: partialInputJson,
            );
          case FrbChatToolCallEndEvent(:final id, :final name, :final input):
            state.finishToolCall(id: id, name: name, input: input);
            yield ToolCallEvent(id: id, name: name, input: input);
          case FrbChatRoundFinishedEvent(:final response, :final metadata):
            final hasEmittedUsage = state.usage != null;
            state.finish(response, metadata: metadata);
            final usage = frbUsageFromResponse(response);
            if (!hasEmittedUsage && usage != null) yield UsageEvent(usage);
            final text = frbString(response['content']);
            if (!state.emittedText && text.isNotEmpty) {
              state.appendText(text);
              yield TextEvent(text);
            }
            finished = true;
          case FrbChatErrorEvent(:final code, :final message):
            yield frbLlmSpan(
              round: roundsUsed == 0 ? nextRound : roundsUsed,
              roundId: roundId,
              startedAt: roundStart,
              state: state,
              requestedModel: model,
              status: AiSpanStatus.error,
              errorCode: code,
              errorMessage: message,
            );
            yield ErrorEvent(message, code: code);
            yield DoneEvent(stopReason: 'error', rounds: roundsUsed);
            return;
          case FrbInvalidChatEvent(:final message):
            yield frbInvalidStreamEventSpan(
              round: roundsUsed == 0 ? nextRound : roundsUsed,
              roundId: roundId,
              startedAt: roundStart,
              state: state,
              requestedModel: model,
              message: message,
            );
            yield ErrorEvent(message, code: 'frb_chat_event_invalid');
            yield DoneEvent(stopReason: 'error', rounds: roundsUsed);
            return;
          case FrbUnknownChatEvent(:final message):
            yield frbLlmSpan(
              round: roundsUsed == 0 ? nextRound : roundsUsed,
              roundId: roundId,
              startedAt: roundStart,
              state: state,
              requestedModel: model,
              status: AiSpanStatus.error,
              errorCode: 'frb_chat_event_unknown',
              errorMessage: message,
            );
            yield ErrorEvent(message, code: 'frb_chat_event_unknown');
            yield DoneEvent(stopReason: 'error', rounds: roundsUsed);
            return;
        }
      }

      if (!finished) {
        yield frbLlmSpan(
          round: roundsUsed == 0 ? nextRound : roundsUsed,
          roundId: roundId,
          startedAt: roundStart,
          state: state,
          requestedModel: model,
          status: AiSpanStatus.error,
          errorCode: 'frb_chat_stream_incomplete',
          errorMessage: 'FRB LLM stream ended without a finished event',
        );
        yield const ErrorEvent(
          'FRB LLM stream ended without a finished event',
          code: 'frb_chat_stream_incomplete',
        );
        yield DoneEvent(stopReason: 'error', rounds: roundsUsed);
        return;
      }

      final roundStatus = _effectiveRoundStatus(state);
      if (roundStatus != 'requires_tool_results' && !doneReceived) {
        yield frbLlmSpan(
          round: roundsUsed == 0 ? nextRound : roundsUsed,
          roundId: roundId,
          startedAt: roundStart,
          state: state,
          requestedModel: model,
          status: AiSpanStatus.error,
          errorCode: _kTerminalDoneMissingErrorCode,
          errorMessage:
              'FRB LLM stream ended after round_finished without terminal done',
        );
        yield const ErrorEvent(
          'FRB LLM stream ended after round_finished without terminal done',
          code: _kTerminalDoneMissingErrorCode,
        );
        yield DoneEvent(stopReason: 'error', rounds: roundsUsed);
        return;
      }
      if (roundStatus == 'requires_tool_results' && doneReceived) {
        yield frbLlmSpan(
          round: roundsUsed == 0 ? nextRound : roundsUsed,
          roundId: roundId,
          startedAt: roundStart,
          state: state,
          requestedModel: model,
          status: AiSpanStatus.error,
          errorCode: 'frb_chat_tool_round_terminal',
          errorMessage:
              'FRB LLM tool round emitted terminal done before tool results',
        );
        yield const ErrorEvent(
          'FRB LLM tool round emitted terminal done before tool results',
          code: 'frb_chat_tool_round_terminal',
        );
        yield DoneEvent(stopReason: 'error', rounds: roundsUsed);
        return;
      }
      if (roundStatus == 'requires_tool_results') {
        final validation = _validateToolCalls(
          state.requiredToolCalls,
          _toolNames(tools),
        );
        if (validation case final failure?) {
          yield frbLlmSpan(
            round: roundsUsed == 0 ? nextRound : roundsUsed,
            roundId: roundId,
            startedAt: roundStart,
            state: state,
            requestedModel: model,
            status: AiSpanStatus.error,
            errorCode: failure.code,
            errorMessage: failure.message,
          );
          yield ErrorEvent(failure.message, code: failure.code);
          yield DoneEvent(stopReason: 'error', rounds: roundsUsed);
          return;
        }
      }

      yield frbLlmSpan(
        round: roundsUsed == 0 ? nextRound : roundsUsed,
        roundId: roundId,
        startedAt: roundStart,
        state: state,
        requestedModel: model,
        status: AiSpanStatus.ok,
      );
      if (roundStatus == 'requires_interaction') {
        final pendingState = state.chatState;
        if (pendingState == null) {
          yield const ErrorEvent(
            'FRB chat requires interaction but did not return chat_state',
            code: 'frb_chat_interaction_state_missing',
          );
          yield DoneEvent(stopReason: 'error', rounds: roundsUsed);
          return;
        }
        if (snapshotStore != null && turnId != null && turnId.isNotEmpty) {
          final snapshot =
              state.chatSnapshot ??
              _buildPendingInteractionSnapshot(state: pendingState);
          snapshotRecord = await snapshotStore.save(
            snapshot: snapshot,
            expectedRevision: snapshotRecord?.revision,
          );
        }
        yield DoneEvent(stopReason: 'requires_interaction', rounds: roundsUsed);
        return;
      }
      if (roundStatus != 'requires_tool_results') {
        final terminalState = state.chatState;
        if (snapshotStore != null &&
            turnId != null &&
            turnId.isNotEmpty &&
            terminalState != null) {
          final terminalSnapshot =
              state.chatSnapshot ??
              _buildTerminalChatSnapshot(
                state: terminalState,
                status: 'completed',
                stopReason: state.doneStopReason ?? state.stopReason,
              );
          snapshotRecord = await snapshotStore.save(
            snapshot: terminalSnapshot,
            expectedRevision: snapshotRecord?.revision,
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
      Map<String, Object?>? activeSnapshot;
      if (snapshotStore != null && turnId != null && turnId.isNotEmpty) {
        activeSnapshot =
            state.chatSnapshot ??
            _buildPendingChatSnapshot(
              state: chatState,
              calls: state.requiredToolCalls,
              tools: tools,
            );
        snapshotRecord = await snapshotStore.save(
          snapshot: activeSnapshot,
          expectedRevision: snapshotRecord?.revision,
        );
      }

      final toolLineHandler = _toolLineHandler;
      if (toolLineHandler == null) {
        yield const ErrorEvent(
          'FRB chat received a tool call without a tool host',
          code: 'frb_chat_tool_host_unavailable',
        );
        yield DoneEvent(stopReason: 'error', rounds: roundsUsed);
        return;
      }

      final dispatcher = AgentRuntimeToolDispatcher(handler: toolLineHandler);
      final resultBlocks = <Map<String, Object?>>[];
      var awaitingUser = false;
      final readOnlyTools = _readOnlyToolNames(tools);
      final readOnlyBatch = <AgentRuntimeToolCall>[];
      for (final call in state.requiredToolCalls) {
        if (cancelToken?.isCancelled == true) {
          yield DoneEvent(stopReason: 'error', rounds: roundsUsed);
          return;
        }
        if (_canParallelizeTool(call, readOnlyTools)) {
          readOnlyBatch.add(call);
          continue;
        }
        if (readOnlyBatch.isNotEmpty) {
          final outcomes = <Future<_ToolDispatchOutcome>>[];
          for (final batchCall in readOnlyBatch) {
            final toolStart = DateTime.now().toUtc();
            yield _toolProgress(batchCall, toolStart);
            if (activeSnapshot != null) {
              activeSnapshot = _withDispatchState(
                activeSnapshot,
                callId: batchCall.stringId,
                status: 'dispatching',
              );
              snapshotRecord = await snapshotStore!.save(
                snapshot: activeSnapshot,
                expectedRevision: snapshotRecord?.revision,
              );
            }
            outcomes.add(
              _dispatchChatTool(
                dispatcher: dispatcher,
                call: batchCall,
                startedAt: toolStart,
                cancelToken: cancelToken,
              ),
            );
          }
          var cancelled = false;
          for (final outcome in await Future.wait(outcomes)) {
            if (outcome.cancelled) {
              if (activeSnapshot != null && snapshotRecord != null) {
                final persisted = await _persistCancelledDispatch(
                  snapshot: activeSnapshot,
                  snapshotRecord: snapshotRecord,
                  store: snapshotStore!,
                  call: outcome.call,
                  replayPolicy: _replayPolicyForTool(tools, outcome.call.name),
                );
                activeSnapshot = persisted.snapshot;
                snapshotRecord = persisted.record;
              }
              cancelled = true;
              yield _toolSpan(outcome, parentId: roundId, round: roundsUsed);
              yield _toolResult(outcome);
              continue;
            }
            yield _toolSpan(outcome, parentId: roundId, round: roundsUsed);
            yield _toolResult(outcome);
            resultBlocks.add(outcome.result.toChatToolResult());
            if (activeSnapshot != null) {
              activeSnapshot = _withDispatchState(
                activeSnapshot,
                callId: outcome.call.stringId,
                status: 'completed',
                result: outcome.result.toChatToolResult(),
              );
              snapshotRecord = await snapshotStore!.save(
                snapshot: activeSnapshot,
                expectedRevision: snapshotRecord?.revision,
              );
            }
          }
          if (cancelled) {
            yield DoneEvent(stopReason: 'error', rounds: roundsUsed);
            return;
          }
          readOnlyBatch.clear();
        }
        final toolStart = DateTime.now().toUtc();
        yield _toolProgress(call, toolStart);
        if (activeSnapshot != null) {
          activeSnapshot = _withDispatchState(
            activeSnapshot,
            callId: call.stringId,
            status: 'dispatching',
          );
          snapshotRecord = await snapshotStore!.save(
            snapshot: activeSnapshot,
            expectedRevision: snapshotRecord?.revision,
          );
        }
        final outcome = await _dispatchChatTool(
          dispatcher: dispatcher,
          call: call,
          startedAt: toolStart,
          cancelToken: cancelToken,
        );
        if (outcome.cancelled) {
          if (activeSnapshot != null && snapshotRecord != null) {
            final persisted = await _persistCancelledDispatch(
              snapshot: activeSnapshot,
              snapshotRecord: snapshotRecord,
              store: snapshotStore!,
              call: call,
              replayPolicy: _replayPolicyForTool(tools, call.name),
            );
            activeSnapshot = persisted.snapshot;
            snapshotRecord = persisted.record;
          }
          yield _toolSpan(outcome, parentId: roundId, round: roundsUsed);
          yield _toolResult(outcome);
          yield DoneEvent(stopReason: 'error', rounds: roundsUsed);
          return;
        }
        yield _toolSpan(outcome, parentId: roundId, round: roundsUsed);
        yield _toolResult(outcome);
        resultBlocks.add(outcome.result.toChatToolResult());
        if (activeSnapshot != null) {
          activeSnapshot = _withDispatchState(
            activeSnapshot,
            callId: call.stringId,
            status: 'completed',
            result: outcome.result.toChatToolResult(),
          );
          snapshotRecord = await snapshotStore!.save(
            snapshot: activeSnapshot,
            expectedRevision: snapshotRecord?.revision,
          );
        }
        if (call.name == kAskUserToolName && !outcome.result.isError) {
          final interaction = _pendingInteractionFromToolResult(outcome.result);
          if (interaction == null) {
            yield frbLlmSpan(
              round: roundsUsed == 0 ? nextRound : roundsUsed,
              roundId: roundId,
              startedAt: roundStart,
              state: state,
              requestedModel: model,
              status: AiSpanStatus.error,
              errorCode: _kInteractionEnvelopeErrorCode,
              errorMessage: _kInteractionEnvelopeErrorMessage,
            );
            yield const ErrorEvent(
              _kInteractionEnvelopeErrorMessage,
              code: _kInteractionEnvelopeErrorCode,
            );
            yield DoneEvent(stopReason: 'error', rounds: roundsUsed);
            return;
          }
          awaitingUser = true;
          suspendInteraction = interaction;
        }
      }
      if (readOnlyBatch.isNotEmpty) {
        final outcomes = <Future<_ToolDispatchOutcome>>[];
        for (final batchCall in readOnlyBatch) {
          final toolStart = DateTime.now().toUtc();
          yield _toolProgress(batchCall, toolStart);
          if (activeSnapshot != null) {
            activeSnapshot = _withDispatchState(
              activeSnapshot,
              callId: batchCall.stringId,
              status: 'dispatching',
            );
            snapshotRecord = await snapshotStore!.save(
              snapshot: activeSnapshot,
              expectedRevision: snapshotRecord?.revision,
            );
          }
          outcomes.add(
            _dispatchChatTool(
              dispatcher: dispatcher,
              call: batchCall,
              startedAt: toolStart,
              cancelToken: cancelToken,
            ),
          );
        }
        var cancelled = false;
        for (final outcome in await Future.wait(outcomes)) {
          if (outcome.cancelled) {
            if (activeSnapshot != null && snapshotRecord != null) {
              final persisted = await _persistCancelledDispatch(
                snapshot: activeSnapshot,
                snapshotRecord: snapshotRecord,
                store: snapshotStore!,
                call: outcome.call,
                replayPolicy: _replayPolicyForTool(tools, outcome.call.name),
              );
              activeSnapshot = persisted.snapshot;
              snapshotRecord = persisted.record;
            }
            cancelled = true;
            yield _toolSpan(outcome, parentId: roundId, round: roundsUsed);
            yield _toolResult(outcome);
            continue;
          }
          yield _toolSpan(outcome, parentId: roundId, round: roundsUsed);
          yield _toolResult(outcome);
          resultBlocks.add(outcome.result.toChatToolResult());
          if (activeSnapshot != null) {
            activeSnapshot = _withDispatchState(
              activeSnapshot,
              callId: outcome.call.stringId,
              status: 'completed',
              result: outcome.result.toChatToolResult(),
            );
            snapshotRecord = await snapshotStore!.save(
              snapshot: activeSnapshot,
              expectedRevision: snapshotRecord?.revision,
            );
          }
        }
        if (cancelled) {
          yield DoneEvent(stopReason: 'error', rounds: roundsUsed);
          return;
        }
      }
      if (awaitingUser) {
        if (suspendInteraction == null) {
          yield const ErrorEvent(
            'FRB chat ask_user result did not produce a pending interaction',
            code: 'frb_chat_interaction_state_missing',
          );
          yield DoneEvent(stopReason: 'error', rounds: roundsUsed);
          return;
        }
        toolResults = resultBlocks;
        continue;
      }
      toolResults = resultBlocks;
    }
  }
}

List<AgentRuntimeContextBlock> _contextBlocksFor(
  ChatAgentTurnRequest request,
) => <AgentRuntimeContextBlock>[
  ...request.contextBlocks,
  if (request.contextPack case final pack?)
    AgentRuntimeContextBlock(
      id: 'naviwealth_context_pack',
      kind: AgentRuntimeContextBlockKind.resource,
      source: 'naviwealth.context_pack',
      priority: 90,
      content: pack.toJson(),
      metadata: const <String, Object?>{
        'authority': 'derived_local_state',
        'trusted_as_instruction': false,
      },
    ),
  if (request.portfolioSnapshot case final snapshot?)
    AgentRuntimeContextBlock(
      id: 'naviwealth_portfolio_snapshot',
      kind: AgentRuntimeContextBlockKind.resource,
      source: 'naviwealth.portfolio_snapshot',
      priority: 75,
      content: snapshot,
      metadata: const <String, Object?>{
        'authority': 'derived_local_state',
        'trusted_as_instruction': false,
      },
    ),
];

Future<_ChatSnapshotRecovery> _recoverChatSnapshot({
  required AgentRuntimeChatSnapshotRecord record,
  required AgentRuntimeChatSnapshotStore store,
  required AgentRuntimeToolLineHandler? toolLineHandler,
  required Set<String> allowedToolNames,
  required CancelToken? cancelToken,
}) async {
  if (record.status == 'requires_interaction') {
    final state = chatSnapshotObject(
      record.snapshot['state'],
      'snapshot.state',
    );
    final round = state['round'] is int ? state['round']! as int : 0;
    return _ChatSnapshotRecovery(
      record: record,
      chatState: state,
      toolResults: const <Map<String, Object?>>[],
      events: const <AiChatEvent>[],
      round: round,
      awaitingUser: true,
      suspendInteraction: null,
    );
  }
  var currentRecord = record;
  var snapshot = Map<String, Object?>.from(record.snapshot);
  final state = chatSnapshotObject(snapshot['state'], 'snapshot.state');
  final round = state['round'] is int ? state['round']! as int : 0;
  final events = <AiChatEvent>[];
  final results = <Map<String, Object?>>[];
  var awaitingUser = false;
  Map<String, Object?>? suspendInteraction;
  final rawDispatches = snapshot['tool_dispatches'];
  if (rawDispatches is! List) {
    return _ChatSnapshotRecovery.failed(
      record: record,
      round: round,
      code: 'frb_chat_snapshot_corrupt',
      message: 'Persisted chat snapshot has no tool dispatch journal',
    );
  }
  final recoveredCalls = <AgentRuntimeToolCall>[];
  for (final value in rawDispatches) {
    final dispatch = chatSnapshotObject(value, 'snapshot.tool_dispatch');
    final callObject = chatSnapshotObject(
      dispatch['call'],
      'snapshot.tool_dispatch.call',
    );
    recoveredCalls.add(
      AgentRuntimeToolCall(
        id: callObject['id'] ?? '',
        name: frbString(callObject['name']),
        input: callObject['input'],
      ),
    );
  }
  if (_validateToolCalls(recoveredCalls, allowedToolNames)
      case final failure?) {
    return _ChatSnapshotRecovery.failed(
      record: record,
      round: round,
      code: failure.code,
      message: failure.message,
    );
  }
  for (var index = 0; index < rawDispatches.length; index++) {
    if (cancelToken?.isCancelled == true) {
      return _ChatSnapshotRecovery.cancelled(
        record: currentRecord,
        round: round,
        events: events,
      );
    }
    final value = rawDispatches[index];
    final dispatch = chatSnapshotObject(value, 'snapshot.tool_dispatch');
    final call = recoveredCalls[index];
    final status = frbString(dispatch['status']);
    if (status == 'completed') {
      final result = chatSnapshotObject(
        dispatch['result'],
        'snapshot.tool_dispatch.result',
      );
      results.add(result);
      // A completed dispatch may be restored after the native stream was
      // interrupted. Re-emit its result so the current chat subscriber sees
      // the recovered tool lifecycle before the next model round.
      events.add(
        ToolCallEvent(id: call.stringId, name: call.name, input: call.input),
      );
      events.add(
        ToolResultEvent(
          id: call.stringId,
          name: call.name,
          output: result['output'],
        ),
      );
      if (call.name == kAskUserToolName && result['is_error'] != true) {
        final interaction = _pendingInteractionFromChatToolResult(result);
        if (interaction == null) {
          return _ChatSnapshotRecovery.failed(
            record: currentRecord,
            round: round,
            code: _kInteractionEnvelopeErrorCode,
            message: _kInteractionEnvelopeErrorMessage,
          );
        }
        awaitingUser = true;
        suspendInteraction = interaction;
      }
      continue;
    }
    final replayPolicy = frbString(dispatch['replay_policy']);
    if (status == 'interrupted' ||
        (status == 'dispatching' && replayPolicy == 'at_most_once')) {
      snapshot = _withDispatchState(
        snapshot,
        callId: call.stringId,
        status: 'interrupted',
      );
      snapshot = <String, Object?>{
        ...snapshot,
        'status': 'failed',
        'error': <String, Object?>{
          'code': 'interrupted_at_most_once',
          'message': "Tool '${call.name}' may already have executed",
        },
      };
      currentRecord = await store.save(
        snapshot: snapshot,
        expectedRevision: currentRecord.revision,
      );
      return _ChatSnapshotRecovery.failed(
        record: currentRecord,
        round: round,
        code: 'frb_chat_at_most_once_interrupted',
        message:
            "Tool '${call.name}' was interrupted after dispatch and cannot "
            'be replayed safely.',
      );
    }
    if (toolLineHandler == null) {
      return _ChatSnapshotRecovery.failed(
        record: currentRecord,
        round: round,
        code: 'frb_chat_tool_host_unavailable',
        message: 'Cannot recover chat tools without a tool host',
      );
    }
    final startedAt = DateTime.now().toUtc();
    events.add(
      ToolCallEvent(id: call.stringId, name: call.name, input: call.input),
    );
    events.add(_toolProgress(call, startedAt));
    snapshot = _withDispatchState(
      snapshot,
      callId: call.stringId,
      status: 'dispatching',
    );
    currentRecord = await store.save(
      snapshot: snapshot,
      expectedRevision: currentRecord.revision,
    );
    final outcome = await _dispatchChatTool(
      dispatcher: AgentRuntimeToolDispatcher(handler: toolLineHandler),
      call: call,
      startedAt: startedAt,
      cancelToken: cancelToken,
    );
    events
      ..add(_toolSpan(outcome, parentId: 'r$round', round: round))
      ..add(_toolResult(outcome));
    if (outcome.cancelled) {
      final persisted = await _persistCancelledDispatch(
        snapshot: snapshot,
        snapshotRecord: currentRecord,
        store: store,
        call: call,
        replayPolicy: replayPolicy,
      );
      return _ChatSnapshotRecovery.cancelled(
        record: persisted.record,
        round: round,
        events: events,
      );
    }
    final result = outcome.result.toChatToolResult();
    results.add(result);
    snapshot = _withDispatchState(
      snapshot,
      callId: call.stringId,
      status: 'completed',
      result: result,
    );
    currentRecord = await store.save(
      snapshot: snapshot,
      expectedRevision: currentRecord.revision,
    );
    if (call.name == kAskUserToolName && !outcome.result.isError) {
      final interaction = _pendingInteractionFromToolResult(outcome.result);
      if (interaction == null) {
        return _ChatSnapshotRecovery.failed(
          record: currentRecord,
          round: round,
          code: _kInteractionEnvelopeErrorCode,
          message: _kInteractionEnvelopeErrorMessage,
        );
      }
      awaitingUser = true;
      suspendInteraction = interaction;
    }
  }
  return _ChatSnapshotRecovery(
    record: currentRecord,
    chatState: state,
    toolResults: results,
    events: events,
    round: round,
    awaitingUser: awaitingUser,
    suspendInteraction: suspendInteraction,
  );
}

Map<String, Object?> _buildPendingInteractionSnapshot({
  required Map<String, Object?> state,
}) {
  return <String, Object?>{
    'protocol_version': 'agent.v1',
    'snapshot_version': kAgentRuntimeChatSnapshotVersion,
    'status': 'requires_interaction',
    'state': state,
    'tool_dispatches': const <Object?>[],
  };
}

Map<String, Object?> _buildPendingChatSnapshot({
  required Map<String, Object?> state,
  required List<AgentRuntimeToolCall> calls,
  required List<Map<String, Object?>> tools,
}) {
  final replayPolicies = <String, String>{
    for (final tool in tools)
      if (tool['name'] case final String name) name: _toolReplayPolicy(tool),
  };
  return <String, Object?>{
    'protocol_version': 'agent.v1',
    'snapshot_version': kAgentRuntimeChatSnapshotVersion,
    'status': 'requires_tool_results',
    'state': state,
    'tool_dispatches': <Object?>[
      for (final call in calls)
        <String, Object?>{
          'call': <String, Object?>{
            'id': call.id,
            'name': call.name,
            'input': call.input,
          },
          'replay_policy': replayPolicies[call.name] ?? 'at_most_once',
          'status': 'pending',
        },
    ],
  };
}

String _toolReplayPolicy(Map<String, Object?> tool) {
  final explicit = tool['replay_policy'];
  if (explicit is String && explicit.isNotEmpty) return explicit;
  return tool['risk'] == 'read_only' ? 'safe_retry' : 'at_most_once';
}

String _replayPolicyForTool(List<Map<String, Object?>> tools, String name) {
  for (final tool in tools) {
    if (tool['name'] == name) return _toolReplayPolicy(tool);
  }
  return 'at_most_once';
}

Map<String, Object?> _buildTerminalChatSnapshot({
  required Map<String, Object?> state,
  required String status,
  required String stopReason,
}) {
  return <String, Object?>{
    'protocol_version': 'agent.v1',
    'snapshot_version': kAgentRuntimeChatSnapshotVersion,
    'status': status,
    'state': state,
    'tool_dispatches': const <Object?>[],
    'stop_reason': stopReason,
  };
}

Map<String, Object?> _withDispatchState(
  Map<String, Object?> snapshot, {
  required String callId,
  required String status,
  Map<String, Object?>? result,
}) {
  final rawDispatches = snapshot['tool_dispatches'];
  if (rawDispatches is! List) {
    throw const AgentRuntimeChatSnapshotException(
      AgentRuntimeChatSnapshotErrorCode.corrupt,
      'chat snapshot tool_dispatches must be an array',
    );
  }
  var found = false;
  final dispatches = <Object?>[
    for (final value in rawDispatches)
      (() {
        final dispatch = Map<String, Object?>.from(
          chatSnapshotObject(value, 'snapshot.tool_dispatch'),
        );
        final call = chatSnapshotObject(
          dispatch['call'],
          'snapshot.tool_dispatch.call',
        );
        if ((call['id']?.toString() ?? '') != callId) return dispatch;
        found = true;
        dispatch['status'] = status;
        if (result == null) {
          dispatch.remove('result');
        } else {
          dispatch['result'] = result;
        }
        return dispatch;
      })(),
  ];
  if (!found) {
    throw AgentRuntimeChatSnapshotException(
      AgentRuntimeChatSnapshotErrorCode.corrupt,
      'chat snapshot does not contain tool call $callId',
    );
  }
  return <String, Object?>{...snapshot, 'tool_dispatches': dispatches};
}

Future<_CancelledDispatchPersistence> _persistCancelledDispatch({
  required Map<String, Object?> snapshot,
  required AgentRuntimeChatSnapshotRecord snapshotRecord,
  required AgentRuntimeChatSnapshotStore store,
  required AgentRuntimeToolCall call,
  required String replayPolicy,
}) async {
  if (replayPolicy != 'at_most_once') {
    return _CancelledDispatchPersistence(
      snapshot: snapshot,
      record: snapshotRecord,
    );
  }
  var failedSnapshot = _withDispatchState(
    snapshot,
    callId: call.stringId,
    status: 'interrupted',
  );
  failedSnapshot = <String, Object?>{
    ...failedSnapshot,
    'status': 'failed',
    'error': <String, Object?>{
      'code': 'interrupted_at_most_once',
      'message': "Tool '${call.name}' may already have executed",
    },
  };
  final record = await store.save(
    snapshot: failedSnapshot,
    expectedRevision: snapshotRecord.revision,
  );
  return _CancelledDispatchPersistence(
    snapshot: failedSnapshot,
    record: record,
  );
}

final class _CancelledDispatchPersistence {
  const _CancelledDispatchPersistence({
    required this.snapshot,
    required this.record,
  });

  final Map<String, Object?> snapshot;
  final AgentRuntimeChatSnapshotRecord record;
}

final class _ChatSnapshotRecovery {
  const _ChatSnapshotRecovery({
    required this.record,
    required this.chatState,
    required this.toolResults,
    required this.events,
    required this.round,
    required this.awaitingUser,
    required this.suspendInteraction,
  }) : errorCode = null,
       errorMessage = null,
       cancelled = false;

  const _ChatSnapshotRecovery.failed({
    required this.record,
    required this.round,
    required String code,
    required String message,
  }) : chatState = null,
       toolResults = const <Map<String, Object?>>[],
       events = const <AiChatEvent>[],
       awaitingUser = false,
       suspendInteraction = null,
       errorCode = code,
       errorMessage = message,
       cancelled = false;

  const _ChatSnapshotRecovery.cancelled({
    required this.record,
    required this.round,
    this.events = const <AiChatEvent>[],
  }) : chatState = null,
       toolResults = const <Map<String, Object?>>[],
       awaitingUser = false,
       suspendInteraction = null,
       errorCode = null,
       errorMessage = null,
       cancelled = true;

  final AgentRuntimeChatSnapshotRecord record;
  final Map<String, Object?>? chatState;
  final List<Map<String, Object?>> toolResults;
  final List<AiChatEvent> events;
  final int round;
  final bool awaitingUser;
  final Map<String, Object?>? suspendInteraction;
  final String? errorCode;
  final String? errorMessage;
  final bool cancelled;
}

Set<String> _readOnlyToolNames(List<Map<String, Object?>> tools) {
  return {
    for (final tool in tools)
      if (tool['risk'] == 'read_only')
        if (tool['name'] case final String name) name,
  };
}

Set<String> _toolNames(List<Map<String, Object?>> tools) {
  return {
    for (final tool in tools)
      if (tool['name'] case final String name)
        if (name.trim().isNotEmpty) name.trim(),
  };
}

String _effectiveRoundStatus(FrbStreamRoundState state) {
  final status = state.status;
  if (status.isNotEmpty) return status;
  return state.stopReason == 'tool_use' ? 'requires_tool_results' : 'completed';
}

({String code, String message})? _validateToolCalls(
  List<AgentRuntimeToolCall> calls,
  Set<String> allowedToolNames,
) {
  if (calls.isEmpty) {
    return (
      code: _kToolNotAllowedErrorCode,
      message: 'FRB LLM requested tool results without a tool call',
    );
  }
  final ids = <String>{};
  for (final call in calls) {
    if (call.stringId.isEmpty || !ids.add(call.stringId)) {
      return (
        code: _kToolNotAllowedErrorCode,
        message: 'FRB LLM returned duplicate or empty tool call ids',
      );
    }
    if (!allowedToolNames.contains(call.name)) {
      return (
        code: _kToolNotAllowedErrorCode,
        message:
            "FRB LLM requested tool '${call.name}', which is not in the active tool catalog",
      );
    }
  }
  final askUserCalls = calls
      .where((call) => call.name == kAskUserToolName)
      .length;
  if (askUserCalls > 0 && calls.length != 1) {
    return (
      code: _kAskUserBatchErrorCode,
      message: 'ask_user must be the only tool call in a round',
    );
  }
  return null;
}

bool _canParallelizeTool(AgentRuntimeToolCall call, Set<String> readOnlyTools) {
  return call.name != kAskUserToolName && readOnlyTools.contains(call.name);
}

Map<String, Object?>? _pendingInteractionFromToolResult(
  AgentRuntimeToolResult result,
) => _pendingInteractionFromOutput(result.output);

Map<String, Object?>? _pendingInteractionFromChatToolResult(
  Map<String, Object?> result,
) {
  if (result['is_error'] == true) return null;
  return _pendingInteractionFromOutput(result['output']);
}

Map<String, Object?>? _pendingInteractionFromOutput(Object? output) {
  final outputObject = frbObjectOrNull(output);
  final interaction = AiInteractionEnvelope.tryParse(
    outputObject?['interaction'],
  );
  if (interaction == null ||
      interaction.status != AiInteractionStatus.pending ||
      interaction.resumeKind != AiInteractionResumeKind.chatTurn) {
    return null;
  }
  return interaction.toJson();
}

ProgressEvent _toolProgress(AgentRuntimeToolCall call, DateTime startedAt) {
  return ProgressEvent(
    LongTaskProgress(
      id: 'tool:${call.stringId}',
      label: 'tool',
      detail: call.name,
      startedAt: startedAt,
    ),
  );
}

Future<_ToolDispatchOutcome> _dispatchChatTool({
  required AgentRuntimeToolDispatcher dispatcher,
  required AgentRuntimeToolCall call,
  required DateTime startedAt,
  CancelToken? cancelToken,
}) async {
  final dispatch = () async {
    final result = await dispatcher.call(call);
    return _ToolDispatchOutcome(
      call: call,
      result: result,
      startedAt: startedAt,
      endedAt: DateTime.now().toUtc(),
    );
  }();
  if (cancelToken == null) return dispatch;
  final outcome = await Future.any<_ToolDispatchOutcome?>([
    dispatch,
    _waitForCancel(cancelToken).then((_) => null),
  ]);
  return outcome ??
      _ToolDispatchOutcome.cancelled(call: call, startedAt: startedAt);
}

SpanEvent _toolSpan(
  _ToolDispatchOutcome outcome, {
  required String parentId,
  required int round,
}) {
  final result = outcome.result;
  final call = outcome.call;
  return SpanEvent(
    id: 'tool:${call.stringId}',
    parentId: parentId,
    kind: AiSpanKind.tool,
    name: 'tool:${call.name}',
    startedAt: outcome.startedAt,
    endedAt: outcome.endedAt,
    status: outcome.cancelled
        ? AiSpanStatus.cancelled
        : result.isError
        ? AiSpanStatus.error
        : AiSpanStatus.ok,
    errorCode: result.errorCode,
    input: call.input,
    output: result.output,
    attributes: <String, Object?>{'round': round, 'tool_use_id': call.id},
  );
}

ToolResultEvent _toolResult(_ToolDispatchOutcome outcome) {
  return ToolResultEvent(
    id: outcome.call.stringId,
    name: outcome.call.name,
    output: outcome.result.output,
  );
}

class _ToolDispatchOutcome {
  const _ToolDispatchOutcome({
    required this.call,
    required this.result,
    required this.startedAt,
    required this.endedAt,
    this.cancelled = false,
  });

  factory _ToolDispatchOutcome.cancelled({
    required AgentRuntimeToolCall call,
    required DateTime startedAt,
  }) {
    final output = <String, Object?>{
      'code': _kToolCancelledErrorCode,
      'message': _kToolCancelledMessage,
    };
    return _ToolDispatchOutcome(
      call: call,
      result: AgentRuntimeToolResult(
        id: call.id,
        name: call.name,
        response: <String, Object?>{
          'jsonrpc': '2.0',
          'id': call.id,
          'error': output,
        },
        output: output,
        outcome: <String, Object?>{
          'status': 'cancelled',
          'retryable': true,
          'code': _kToolCancelledErrorCode,
          'message': _kToolCancelledMessage,
          'details': const <String, Object?>{},
        },
        isError: true,
      ),
      startedAt: startedAt,
      endedAt: DateTime.now().toUtc(),
      cancelled: true,
    );
  }

  final AgentRuntimeToolCall call;
  final AgentRuntimeToolResult result;
  final DateTime startedAt;
  final DateTime endedAt;
  final bool cancelled;
}

Stream<Map<String, Object?>> _cancelableFrbStream(
  Stream<Map<String, Object?>> source,
  CancelToken? cancelToken,
) async* {
  if (cancelToken == null) {
    yield* source;
    return;
  }

  final iterator = StreamIterator<Map<String, Object?>>(source);
  final cancellation = _waitForCancel(cancelToken)
      .then((_) => const _FrbStreamOutcome.cancelled());
  try {
    while (true) {
      if (cancelToken.isCancelled) {
        yield const <String, Object?>{'kind': kFrbChatStreamCancelledKind};
        return;
      }
      final outcome = await Future.any<_FrbStreamOutcome>([
        iterator.moveNext().then(
          (hasNext) => hasNext
              ? _FrbStreamOutcome.event(iterator.current)
              : const _FrbStreamOutcome.done(),
        ),
        cancellation,
      ]);
      if (outcome.cancelled) {
        yield const <String, Object?>{'kind': kFrbChatStreamCancelledKind};
        return;
      }
      if (outcome.done) return;
      yield outcome.event!;
    }
  } finally {
    await iterator.cancel();
  }
}

Future<void> _waitForCancel(CancelToken cancelToken) async {
  await cancelToken.whenCancel;
}

class _FrbStreamOutcome {
  const _FrbStreamOutcome.event(this.event) : done = false, cancelled = false;

  const _FrbStreamOutcome.done() : event = null, done = true, cancelled = false;

  const _FrbStreamOutcome.cancelled()
    : event = null,
      done = false,
      cancelled = true;

  final Map<String, Object?>? event;
  final bool done;
  final bool cancelled;
}
