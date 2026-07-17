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
    var roundsUsed = 0;
    Map<String, Object?>? chatState;
    var toolResults = const <Map<String, Object?>>[];
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
        );
        snapshotRecord = recovery.record;
        for (final event in recovery.events) {
          yield event;
        }
        if (recovery.errorCode case final code?) {
          yield ErrorEvent(recovery.errorMessage!, code: code);
          yield DoneEvent(stopReason: 'error', rounds: recovery.round);
          return;
        }
        if (recovery.awaitingUser) {
          yield DoneEvent(stopReason: 'end_turn', rounds: recovery.round);
          return;
        }
        chatState = recovery.chatState;
        toolResults = recovery.toolResults;
        roundsUsed = recovery.round;
      }
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
        ),
        cancelToken,
      );
      toolResults = const <Map<String, Object?>>[];
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

      yield frbLlmSpan(
        round: roundsUsed == 0 ? nextRound : roundsUsed,
        roundId: roundId,
        startedAt: roundStart,
        state: state,
        requestedModel: model,
        status: AiSpanStatus.ok,
      );
      if (state.status != 'requires_tool_results') {
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
              ),
            );
          }
          for (final outcome in await Future.wait(outcomes)) {
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
        );
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
          awaitingUser = true;
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
            ),
          );
        }
        for (final outcome in await Future.wait(outcomes)) {
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
      }
      if (awaitingUser) {
        yield DoneEvent(stopReason: 'end_turn', rounds: roundsUsed);
        return;
      }
      toolResults = resultBlocks;
    }
  }
}

Future<_ChatSnapshotRecovery> _recoverChatSnapshot({
  required AgentRuntimeChatSnapshotRecord record,
  required AgentRuntimeChatSnapshotStore store,
  required AgentRuntimeToolLineHandler? toolLineHandler,
}) async {
  var currentRecord = record;
  var snapshot = Map<String, Object?>.from(record.snapshot);
  final state = chatSnapshotObject(snapshot['state'], 'snapshot.state');
  final round = state['round'] is int ? state['round']! as int : 0;
  final events = <AiChatEvent>[];
  final results = <Map<String, Object?>>[];
  var awaitingUser = false;
  final rawDispatches = snapshot['tool_dispatches'];
  if (rawDispatches is! List) {
    return _ChatSnapshotRecovery.failed(
      record: record,
      round: round,
      code: 'frb_chat_snapshot_corrupt',
      message: 'Persisted chat snapshot has no tool dispatch journal',
    );
  }
  for (final value in rawDispatches) {
    final dispatch = chatSnapshotObject(value, 'snapshot.tool_dispatch');
    final callObject = chatSnapshotObject(
      dispatch['call'],
      'snapshot.tool_dispatch.call',
    );
    final call = AgentRuntimeToolCall(
      id: callObject['id'] ?? '',
      name: frbString(callObject['name']),
      input: callObject['input'],
    );
    final status = frbString(dispatch['status']);
    if (status == 'completed') {
      final result = chatSnapshotObject(
        dispatch['result'],
        'snapshot.tool_dispatch.result',
      );
      results.add(result);
      if (call.name == kAskUserToolName && result['is_error'] != true) {
        awaitingUser = true;
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
    );
    events
      ..add(_toolSpan(outcome, parentId: 'r$round', round: round))
      ..add(_toolResult(outcome));
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
      awaitingUser = true;
    }
  }
  return _ChatSnapshotRecovery(
    record: currentRecord,
    chatState: state,
    toolResults: results,
    events: events,
    round: round,
    awaitingUser: awaitingUser,
  );
}

Map<String, Object?> _buildPendingChatSnapshot({
  required Map<String, Object?> state,
  required List<AgentRuntimeToolCall> calls,
  required List<Map<String, Object?>> tools,
}) {
  final replayPolicies = <String, String>{
    for (final tool in tools)
      if (tool['name'] case final String name)
        name:
            tool['replay_policy'] as String? ??
            (tool['risk'] == 'read_only' ? 'safe_retry' : 'at_most_once'),
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

final class _ChatSnapshotRecovery {
  const _ChatSnapshotRecovery({
    required this.record,
    required this.chatState,
    required this.toolResults,
    required this.events,
    required this.round,
    required this.awaitingUser,
  }) : errorCode = null,
       errorMessage = null;

  const _ChatSnapshotRecovery.failed({
    required this.record,
    required this.round,
    required String code,
    required String message,
  }) : chatState = null,
       toolResults = const <Map<String, Object?>>[],
       events = const <AiChatEvent>[],
       awaitingUser = false,
       errorCode = code,
       errorMessage = message;

  final AgentRuntimeChatSnapshotRecord record;
  final Map<String, Object?>? chatState;
  final List<Map<String, Object?>> toolResults;
  final List<AiChatEvent> events;
  final int round;
  final bool awaitingUser;
  final String? errorCode;
  final String? errorMessage;
}

Set<String> _readOnlyToolNames(List<Map<String, Object?>> tools) {
  return {
    for (final tool in tools)
      if (tool['risk'] == 'read_only')
        if (tool['name'] case final String name) name,
  };
}

bool _canParallelizeTool(AgentRuntimeToolCall call, Set<String> readOnlyTools) {
  return call.name != kAskUserToolName && readOnlyTools.contains(call.name);
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
}) async {
  final result = await dispatcher.call(call);
  return _ToolDispatchOutcome(
    call: call,
    result: result,
    startedAt: startedAt,
    endedAt: DateTime.now().toUtc(),
  );
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
    status: result.isError ? AiSpanStatus.error : AiSpanStatus.ok,
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
  });

  final AgentRuntimeToolCall call;
  final AgentRuntimeToolResult result;
  final DateTime startedAt;
  final DateTime endedAt;
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
  final cancellation = _waitForCancel(
    cancelToken,
  ).then((_) => const _FrbStreamOutcome.cancelled());
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
