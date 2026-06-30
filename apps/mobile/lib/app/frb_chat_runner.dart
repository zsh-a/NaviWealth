/// FRB-backed adapter for the existing AI Chat runner seam.
///
/// The native FRB LLM API now exposes a primitive JSON event stream. This runner
/// maps those native events into the existing `AiChatEvent` vocabulary. Tool
/// calls are executed through the JSON-RPC tool host and fed back into bounded
/// follow-up LLM rounds, matching the existing device loop contract.
library;

import 'dart:async';

import 'package:dio/dio.dart';

import '../core/ai/contracts/contracts.dart';
import '../core/ai/progress/long_task_progress.dart';
import '../core/ai/runtime/ai_runtime.dart';
import '../core/ai/runtime/device/tools/ask_user_tool.dart'
    show kAskUserToolName;
import '../features/ai_chat/data/ai_chat_api_client.dart';
import 'agent_runtime_llm_bridge.dart';
import 'agent_runtime_llm_stream_bridge.dart';
import 'frb_chat_tool_dispatcher.dart';
import 'frb_chat_trace_mapper.dart';
import 'frb_chat_types.dart';

const String kFrbChatRunnerAgentId = 'ai_chat';
const String _kFrbStreamCancelledKind = '__frb_stream_cancelled';

class FrbChatRunner implements DeviceChatRunner {
  const FrbChatRunner({
    required AgentRuntimeLlmBridge llmBridge,
    AgentRuntimeLlmStreamBridge? streamBridge,
    List<Map<String, Object?>> tools = const <Map<String, Object?>>[],
    FrbChatToolLineHandler? toolLineHandler,
    int maxToolRounds = 4,
    String agentId = kFrbChatRunnerAgentId,
  }) : _llmBridge = llmBridge,
       _streamBridge = streamBridge,
       _tools = tools,
       _toolLineHandler = toolLineHandler,
       _maxToolRounds = maxToolRounds,
       _agentId = agentId;

  final AgentRuntimeLlmBridge _llmBridge;
  final AgentRuntimeLlmStreamBridge? _streamBridge;
  final List<Map<String, Object?>> _tools;
  final FrbChatToolLineHandler? _toolLineHandler;
  final int _maxToolRounds;
  final String _agentId;

  @override
  Stream<AiChatEvent> run({
    required List<WireMessage> messages,
    Map<String, Object?>? portfolioSnapshot,
    ContextPack? contextPack,
    String? model,
    CancelToken? cancelToken,
  }) async* {
    if (cancelToken?.isCancelled == true) {
      yield const DoneEvent(stopReason: 'error', rounds: 0);
      return;
    }

    try {
      final streamBridge = _streamBridge;
      if (streamBridge != null) {
        yield* _runStream(
          streamBridge: streamBridge,
          messages: messages,
          portfolioSnapshot: portfolioSnapshot,
          contextPack: contextPack,
          model: model,
          cancelToken: cancelToken,
        );
        return;
      }
      final roundStart = DateTime.now().toUtc();
      final response = await _llmBridge.completeProfile(
        messages: <Map<String, Object?>>[
          for (final message in messages) message.toJson(),
        ],
        tools: _tools,
        metadata: <String, Object?>{
          'agent_id': _agentId,
          'surface': 'ai_chat',
          'requested_model': ?model,
          'portfolio_snapshot': ?portfolioSnapshot,
          'context_pack': ?contextPack?.toJson(),
          'streaming': false,
        },
      );
      if (cancelToken?.isCancelled == true) {
        yield const DoneEvent(stopReason: 'error', rounds: 0);
        return;
      }

      final usage = frbUsageFromResponse(response);
      if (usage != null) yield UsageEvent(usage);

      final text = frbString(response['content']);
      if (text.isNotEmpty) yield TextEvent(text);
      yield frbCompletionSpan(
        startedAt: roundStart,
        response: response,
        inputMessageCount: messages.length,
        requestedModel: model,
      );

      yield DoneEvent(
        stopReason: frbChatStopReason(frbString(response['finish_reason'])),
        rounds: 1,
      );
    } catch (error) {
      yield ErrorEvent(error.toString(), code: 'frb_chat_error');
      yield const DoneEvent(stopReason: 'error', rounds: 1);
    }
  }

  Stream<AiChatEvent> _runStream({
    required AgentRuntimeLlmStreamBridge streamBridge,
    required List<WireMessage> messages,
    Map<String, Object?>? portfolioSnapshot,
    ContextPack? contextPack,
    String? model,
    CancelToken? cancelToken,
  }) async* {
    final initialMessages = <Map<String, Object?>>[
      for (final message in messages) message.toJson(),
    ];
    var roundsUsed = 0;
    Map<String, Object?>? chatState;
    var toolResults = const <Map<String, Object?>>[];
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
          tools: _tools,
          metadata: <String, Object?>{
            'agent_id': _agentId,
            'surface': 'ai_chat',
            'requested_model': ?model,
            'portfolio_snapshot': ?portfolioSnapshot,
            'context_pack': ?contextPack?.toJson(),
            'streaming': true,
            'round': nextRound,
          },
          maxToolRounds: _maxToolRounds,
          chatState: chatState,
          toolResults: toolResults,
        ),
        cancelToken,
      );
      toolResults = const <Map<String, Object?>>[];
      await for (final event in stream) {
        final eventRound = frbInt(event['round']);
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
        switch (frbString(event['kind'])) {
          case _kFrbStreamCancelledKind:
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
          case 'started':
          case 'llm_started':
          case 'usage':
            break;
          case 'done':
            state.finishDone(frbObject(event['metadata']));
            break;
          case 'delta':
            final text = frbString(event['content']);
            if (text.isNotEmpty) {
              state.appendText(text);
              yield TextEvent(text);
            }
          case 'thinking_delta':
            final text = frbString(event['content']);
            if (text.isNotEmpty) {
              state.appendThinking(text);
              yield ThinkingDeltaEvent(text);
            }
          case 'thinking_signature_delta':
            state.appendThinkingSignature(frbString(event['content']));
          case 'tool_call_start':
            final id = frbString(event['tool_call_id']);
            final name = frbString(event['tool_name']);
            if (id.isEmpty || name.isEmpty) {
              yield frbInvalidStreamEventSpan(
                round: roundsUsed == 0 ? nextRound : roundsUsed,
                roundId: roundId,
                startedAt: roundStart,
                state: state,
                requestedModel: model,
                message:
                    'FRB LLM tool_call_start event requires tool_call_id and tool_name',
              );
              yield const ErrorEvent(
                'FRB LLM tool_call_start event requires tool_call_id and tool_name',
                code: 'frb_chat_event_invalid',
              );
              yield DoneEvent(stopReason: 'error', rounds: roundsUsed);
              return;
            }
            state.startToolCall(id: id, name: name);
            yield ToolCallStartEvent(id: id, name: name);
          case 'tool_call_delta':
            final id = frbString(event['tool_call_id']);
            if (id.isEmpty) {
              yield frbInvalidStreamEventSpan(
                round: roundsUsed == 0 ? nextRound : roundsUsed,
                roundId: roundId,
                startedAt: roundStart,
                state: state,
                requestedModel: model,
                message: 'FRB LLM tool_call_delta event requires tool_call_id',
              );
              yield const ErrorEvent(
                'FRB LLM tool_call_delta event requires tool_call_id',
                code: 'frb_chat_event_invalid',
              );
              yield DoneEvent(stopReason: 'error', rounds: roundsUsed);
              return;
            }
            final partialInputJson = frbString(event['partial_input_json']);
            state.appendToolInput(id: id, partialInputJson: partialInputJson);
            yield ToolCallDeltaEvent(
              id: id,
              partialInputJson: partialInputJson,
            );
          case 'tool_call_end':
            final id = frbString(event['tool_call_id']);
            final name = frbString(event['tool_name']);
            if (id.isEmpty || name.isEmpty) {
              yield frbInvalidStreamEventSpan(
                round: roundsUsed == 0 ? nextRound : roundsUsed,
                roundId: roundId,
                startedAt: roundStart,
                state: state,
                requestedModel: model,
                message:
                    'FRB LLM tool_call_end event requires tool_call_id and tool_name',
              );
              yield const ErrorEvent(
                'FRB LLM tool_call_end event requires tool_call_id and tool_name',
                code: 'frb_chat_event_invalid',
              );
              yield DoneEvent(stopReason: 'error', rounds: roundsUsed);
              return;
            }
            final input = frbToolInput(event['tool_input']);
            state.finishToolCall(id: id, name: name, input: input);
            yield ToolCallEvent(id: id, name: name, input: input);
          case 'finished':
          case 'round_finished':
            final response = frbObjectOrNull(event['response']);
            if (response == null) {
              final kind = frbString(event['kind']);
              yield frbInvalidStreamEventSpan(
                round: roundsUsed == 0 ? nextRound : roundsUsed,
                roundId: roundId,
                startedAt: roundStart,
                state: state,
                requestedModel: model,
                message: 'FRB LLM $kind event response is not an object',
              );
              yield ErrorEvent(
                'FRB LLM $kind event response is not an object',
                code: 'frb_chat_event_invalid',
              );
              yield DoneEvent(stopReason: 'error', rounds: roundsUsed);
              return;
            }
            state.finish(response, metadata: frbObject(event['metadata']));
            final usage = frbUsageFromResponse(response);
            if (usage != null) yield UsageEvent(usage);
            final text = frbString(response['content']);
            if (!state.emittedText && text.isNotEmpty) {
              state.appendText(text);
              yield TextEvent(text);
            }
            finished = true;
          case 'error':
            final metadata = frbObject(event['metadata']);
            yield frbLlmSpan(
              round: roundsUsed == 0 ? nextRound : roundsUsed,
              roundId: roundId,
              startedAt: roundStart,
              state: state,
              requestedModel: model,
              status: AiSpanStatus.error,
              errorCode: frbString(metadata['code']).isEmpty
                  ? 'frb_chat_error'
                  : frbString(metadata['code']),
              errorMessage: frbString(metadata['message']).isEmpty
                  ? 'frb_chat_error'
                  : frbString(metadata['message']),
            );
            yield ErrorEvent(
              frbString(metadata['message']).isEmpty
                  ? 'frb_chat_error'
                  : frbString(metadata['message']),
              code: frbString(metadata['code']).isEmpty
                  ? 'frb_chat_error'
                  : frbString(metadata['code']),
            );
            yield DoneEvent(stopReason: 'error', rounds: roundsUsed);
            return;
          default:
            yield frbLlmSpan(
              round: roundsUsed == 0 ? nextRound : roundsUsed,
              roundId: roundId,
              startedAt: roundStart,
              state: state,
              requestedModel: model,
              status: AiSpanStatus.error,
              errorCode: 'frb_chat_event_unknown',
              errorMessage:
                  'unknown FRB LLM stream event kind: ${event['kind']}',
            );
            yield ErrorEvent(
              'unknown FRB LLM stream event kind: ${event['kind']}',
              code: 'frb_chat_event_unknown',
            );
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

      final toolLineHandler = _toolLineHandler;
      if (toolLineHandler == null) {
        yield const ErrorEvent(
          'FRB chat received a tool call without a tool host',
          code: 'frb_chat_tool_host_unavailable',
        );
        yield DoneEvent(stopReason: 'error', rounds: roundsUsed);
        return;
      }

      final dispatcher = FrbChatToolDispatcher(handler: toolLineHandler);
      final resultBlocks = <Map<String, Object?>>[];
      var awaitingUser = false;
      for (final call in state.requiredToolCalls) {
        if (cancelToken?.isCancelled == true) {
          yield DoneEvent(stopReason: 'error', rounds: roundsUsed);
          return;
        }
        final toolStart = DateTime.now().toUtc();
        yield ProgressEvent(
          LongTaskProgress(
            id: 'tool:${call.id}',
            label: 'tool',
            detail: call.name,
            startedAt: toolStart,
          ),
        );
        final result = await dispatcher.call(call);
        yield SpanEvent(
          id: 'tool:${call.id}',
          parentId: roundId,
          kind: AiSpanKind.tool,
          name: 'tool:${call.name}',
          startedAt: toolStart,
          endedAt: DateTime.now().toUtc(),
          status: result.isError ? AiSpanStatus.error : AiSpanStatus.ok,
          errorCode: result.errorCode,
          input: call.input,
          output: result.output,
          attributes: <String, Object?>{
            'round': roundsUsed,
            'tool_use_id': call.id,
          },
        );
        yield ToolResultEvent(
          id: call.id,
          name: call.name,
          output: result.output,
        );
        resultBlocks.add(result.toChatToolResult());
        if (call.name == kAskUserToolName && !result.isError) {
          awaitingUser = true;
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
        yield const <String, Object?>{'kind': _kFrbStreamCancelledKind};
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
        yield const <String, Object?>{'kind': _kFrbStreamCancelledKind};
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
