/// FRB-backed adapter for the existing AI Chat runner seam.
///
/// The native FRB LLM API now exposes a primitive JSON event stream. This runner
/// maps those native events into the existing `AiChatEvent` vocabulary. Tool
/// call delta parity still needs native event support, so production chat should
/// not switch to this runner until that contract is complete.
library;

import 'package:dio/dio.dart';

import '../core/ai/contracts/contracts.dart';
import '../core/ai/runtime/ai_runtime.dart';
import '../features/ai_chat/data/ai_chat_api_client.dart';
import 'agent_runtime_llm_bridge.dart';
import 'agent_runtime_llm_stream_bridge.dart';

const String kFrbChatRunnerAgentId = 'ai_chat';

class FrbChatRunner implements DeviceChatRunner {
  const FrbChatRunner({
    required AgentRuntimeLlmBridge llmBridge,
    AgentRuntimeLlmStreamBridge? streamBridge,
    String agentId = kFrbChatRunnerAgentId,
  }) : _llmBridge = llmBridge,
       _streamBridge = streamBridge,
       _agentId = agentId;

  final AgentRuntimeLlmBridge _llmBridge;
  final AgentRuntimeLlmStreamBridge? _streamBridge;
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
      final response = await _llmBridge.completeProfile(
        messages: <Map<String, Object?>>[
          for (final message in messages) message.toJson(),
        ],
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

      final usage = _usageFromResponse(response);
      if (usage != null) yield UsageEvent(usage);

      final text = _string(response['content']);
      if (text.isNotEmpty) yield TextEvent(text);

      yield DoneEvent(
        stopReason: _chatStopReason(_string(response['finish_reason'])),
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
    var emittedText = false;
    var finished = false;
    await for (final event in streamBridge.streamProfile(
      messages: <Map<String, Object?>>[
        for (final message in messages) message.toJson(),
      ],
      metadata: <String, Object?>{
        'agent_id': _agentId,
        'surface': 'ai_chat',
        'requested_model': ?model,
        'portfolio_snapshot': ?portfolioSnapshot,
        'context_pack': ?contextPack?.toJson(),
        'streaming': true,
      },
    )) {
      if (cancelToken?.isCancelled == true) {
        yield const DoneEvent(stopReason: 'error', rounds: 0);
        return;
      }
      switch (_string(event['kind'])) {
        case 'started':
          break;
        case 'delta':
          final text = _string(event['content']);
          if (text.isNotEmpty) {
            emittedText = true;
            yield TextEvent(text);
          }
        case 'finished':
          final response = _object(event['response']);
          final usage = _usageFromResponse(response);
          if (usage != null) yield UsageEvent(usage);
          final text = _string(response['content']);
          if (!emittedText && text.isNotEmpty) yield TextEvent(text);
          finished = true;
          yield DoneEvent(
            stopReason: _chatStopReason(_string(response['finish_reason'])),
            rounds: 1,
          );
        case 'error':
          final metadata = _object(event['metadata']);
          yield ErrorEvent(
            _string(metadata['message']).isEmpty
                ? 'frb_chat_error'
                : _string(metadata['message']),
            code: _string(metadata['code']).isEmpty
                ? 'frb_chat_error'
                : _string(metadata['code']),
          );
          yield const DoneEvent(stopReason: 'error', rounds: 1);
          return;
        default:
          yield ErrorEvent(
            'unknown FRB LLM stream event kind: ${event['kind']}',
            code: 'frb_chat_event_unknown',
          );
          yield const DoneEvent(stopReason: 'error', rounds: 1);
          return;
      }
    }
    if (!finished) {
      yield const ErrorEvent(
        'FRB LLM stream ended without a finished event',
        code: 'frb_chat_stream_incomplete',
      );
      yield const DoneEvent(stopReason: 'error', rounds: 1);
    }
  }
}

TokenUsage? _usageFromResponse(Map<String, Object?> response) {
  final usage = response['usage'];
  if (usage is! Map) return null;
  return TokenUsage(
    input: _int(usage['input_tokens'] ?? usage['input']),
    output: _int(usage['output_tokens'] ?? usage['output']),
    cacheRead: _int(usage['cache_read_tokens'] ?? usage['cache_read']),
    cacheWrite: _int(usage['cache_write_tokens'] ?? usage['cache_write']),
  );
}

String _chatStopReason(String reason) {
  return switch (reason) {
    'stop' => 'end_turn',
    'length' => 'max_tokens',
    'tool_call' || 'tool_calls' || 'tool_use' => 'tool_use',
    'content_filter' => 'refusal',
    'error' => 'error',
    _ when reason.isNotEmpty => reason,
    _ => 'end_turn',
  };
}

String _string(Object? value) => value is String ? value : '';

Map<String, Object?> _object(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return const <String, Object?>{};
}

int _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return 0;
}
