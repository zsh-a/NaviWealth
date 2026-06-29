/// FRB-backed adapter for the existing AI Chat runner seam.
///
/// This is an integration bridge, not the final chat streaming runtime. The
/// current native FRB LLM API returns a completed response, while AI Chat still
/// expects a `Stream<AiChatEvent>` for text deltas, cancellation, tool-call
/// deltas, and trace capture. This runner converts one FRB completion into the
/// existing event vocabulary so the Flutter chat seam can be exercised through
/// FRB without pretending token-level streaming parity exists yet.
library;

import 'package:dio/dio.dart';

import '../core/ai/contracts/contracts.dart';
import '../core/ai/runtime/ai_runtime.dart';
import '../features/ai_chat/data/ai_chat_api_client.dart';
import 'agent_runtime_llm_bridge.dart';

const String kFrbChatRunnerAgentId = 'ai_chat';

class FrbChatRunner implements DeviceChatRunner {
  const FrbChatRunner({
    required AgentRuntimeLlmBridge llmBridge,
    String agentId = kFrbChatRunnerAgentId,
  }) : _llmBridge = llmBridge,
       _agentId = agentId;

  final AgentRuntimeLlmBridge _llmBridge;
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

int _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return 0;
}
