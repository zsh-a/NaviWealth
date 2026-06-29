/// FRB-backed adapter for the existing AI Chat runner seam.
///
/// The native FRB LLM API now exposes a primitive JSON event stream. This runner
/// maps those native events into the existing `AiChatEvent` vocabulary. Tool
/// calls are executed through the JSON-RPC tool host and fed back into bounded
/// follow-up LLM rounds, matching the existing device loop contract.
library;

import 'dart:convert';

import 'package:dio/dio.dart';

import '../core/ai/contracts/contracts.dart';
import '../core/ai/runtime/ai_runtime.dart';
import '../features/ai_chat/data/ai_chat_api_client.dart';
import 'agent_runtime_llm_bridge.dart';
import 'agent_runtime_llm_stream_bridge.dart';

const String kFrbChatRunnerAgentId = 'ai_chat';

typedef FrbChatToolLineHandler = Future<String> Function(String line);

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
    final conversation = <Map<String, Object?>>[
      for (final message in messages) message.toJson(),
    ];
    var roundsUsed = 0;
    for (var round = 1; round <= _maxToolRounds; round++) {
      roundsUsed = round;
      final state = _FrbStreamRoundState();
      var finished = false;
      await for (final event in streamBridge.streamProfile(
        messages: conversation,
        tools: _tools,
        metadata: <String, Object?>{
          'agent_id': _agentId,
          'surface': 'ai_chat',
          'requested_model': ?model,
          'portfolio_snapshot': ?portfolioSnapshot,
          'context_pack': ?contextPack?.toJson(),
          'streaming': true,
          'round': round,
        },
      )) {
        if (cancelToken?.isCancelled == true) {
          yield DoneEvent(stopReason: 'error', rounds: roundsUsed);
          return;
        }
        switch (_string(event['kind'])) {
          case 'started':
            break;
          case 'delta':
            final text = _string(event['content']);
            if (text.isNotEmpty) {
              state.appendText(text);
              yield TextEvent(text);
            }
          case 'thinking_delta':
            final text = _string(event['content']);
            if (text.isNotEmpty) {
              state.appendThinking(text);
              yield ThinkingDeltaEvent(text);
            }
          case 'thinking_signature_delta':
            state.appendThinkingSignature(_string(event['content']));
          case 'tool_call_start':
            final id = _string(event['tool_call_id']);
            final name = _string(event['tool_name']);
            state.startToolCall(id: id, name: name);
            yield ToolCallStartEvent(id: id, name: name);
          case 'tool_call_delta':
            final id = _string(event['tool_call_id']);
            final partialInputJson = _string(event['partial_input_json']);
            state.appendToolInput(id: id, partialInputJson: partialInputJson);
            yield ToolCallDeltaEvent(
              id: id,
              partialInputJson: partialInputJson,
            );
          case 'tool_call_end':
            final id = _string(event['tool_call_id']);
            final name = _string(event['tool_name']);
            final input = _toolInput(event['tool_input']);
            state.finishToolCall(id: id, name: name, input: input);
            yield ToolCallEvent(id: id, name: name, input: input);
          case 'finished':
            final response = _object(event['response']);
            state.finish(response);
            final usage = _usageFromResponse(response);
            if (usage != null) yield UsageEvent(usage);
            final text = _string(response['content']);
            if (!state.emittedText && text.isNotEmpty) {
              state.appendText(text);
              yield TextEvent(text);
            }
            finished = true;
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
            yield DoneEvent(stopReason: 'error', rounds: roundsUsed);
            return;
          default:
            yield ErrorEvent(
              'unknown FRB LLM stream event kind: ${event['kind']}',
              code: 'frb_chat_event_unknown',
            );
            yield DoneEvent(stopReason: 'error', rounds: roundsUsed);
            return;
        }
      }

      if (!finished) {
        yield const ErrorEvent(
          'FRB LLM stream ended without a finished event',
          code: 'frb_chat_stream_incomplete',
        );
        yield DoneEvent(stopReason: 'error', rounds: roundsUsed);
        return;
      }

      final stopReason = state.stopReason;
      final toolCalls = state.toolCalls;
      if (stopReason != 'tool_use' || toolCalls.isEmpty) {
        yield DoneEvent(stopReason: stopReason, rounds: roundsUsed);
        return;
      }
      if (round == _maxToolRounds) {
        yield const ErrorEvent(
          'FRB chat exceeded the tool round budget',
          code: 'frb_chat_tool_round_budget_exceeded',
        );
        yield DoneEvent(stopReason: 'error', rounds: roundsUsed);
        return;
      }

      final handler = _toolLineHandler;
      if (handler == null) {
        yield const ErrorEvent(
          'FRB chat received a tool call without a tool host',
          code: 'frb_chat_tool_host_unavailable',
        );
        yield DoneEvent(stopReason: 'error', rounds: roundsUsed);
        return;
      }

      conversation.add(state.assistantMessage());
      final resultBlocks = <Map<String, Object?>>[];
      for (final call in toolCalls) {
        if (cancelToken?.isCancelled == true) {
          yield DoneEvent(stopReason: 'error', rounds: roundsUsed);
          return;
        }
        final result = await _runToolCall(handler, call);
        yield ToolResultEvent(
          id: call.id,
          name: call.name,
          output: result.output,
        );
        resultBlocks.add(result.toToolResultBlock());
      }
      conversation.add(<String, Object?>{
        'role': 'user',
        'content': resultBlocks,
      });
    }

    yield const ErrorEvent(
      'FRB chat exceeded the tool round budget',
      code: 'frb_chat_tool_round_budget_exceeded',
    );
    yield DoneEvent(stopReason: 'error', rounds: roundsUsed);
  }
}

Future<_FrbToolResult> _runToolCall(
  FrbChatToolLineHandler handler,
  _FrbToolCall call,
) async {
  try {
    final line = jsonEncode(<String, Object?>{
      'jsonrpc': '2.0',
      'id': call.id,
      'method': 'tool.call',
      'params': <String, Object?>{
        'name': call.name,
        'input': call.input ?? const <String, Object?>{},
      },
    });
    final response = _object(jsonDecode(await handler(line)));
    final error = response['error'];
    if (error != null) {
      return _FrbToolResult(
        id: call.id,
        name: call.name,
        output: error,
        isError: true,
      );
    }
    return _FrbToolResult(
      id: call.id,
      name: call.name,
      output: response['result'],
    );
  } catch (error) {
    return _FrbToolResult(
      id: call.id,
      name: call.name,
      output: <String, Object?>{
        'code': 'frb_chat_tool_dispatch_failed',
        'message': error.toString(),
      },
      isError: true,
    );
  }
}

class _FrbStreamRoundState {
  final StringBuffer _text = StringBuffer();
  final StringBuffer _thinking = StringBuffer();
  final StringBuffer _thinkingSignature = StringBuffer();
  final Map<String, _FrbToolCallBuilder> _toolCalls =
      <String, _FrbToolCallBuilder>{};
  Map<String, Object?> _response = const <String, Object?>{};

  bool get emittedText => _text.isNotEmpty;

  String get stopReason => _chatStopReason(_string(_response['finish_reason']));

  List<_FrbToolCall> get toolCalls {
    return [
      for (final entry in _toolCalls.entries) entry.value.finish(id: entry.key),
    ];
  }

  void appendText(String text) => _text.write(text);

  void appendThinking(String text) => _thinking.write(text);

  void appendThinkingSignature(String value) {
    if (value.isNotEmpty) _thinkingSignature.write(value);
  }

  void startToolCall({required String id, required String name}) {
    _toolCalls.putIfAbsent(id, () => _FrbToolCallBuilder()).name = name;
  }

  void appendToolInput({required String id, required String partialInputJson}) {
    _toolCalls
        .putIfAbsent(id, () => _FrbToolCallBuilder())
        .partialInputJson
        .write(partialInputJson);
  }

  void finishToolCall({
    required String id,
    required String name,
    required Object? input,
  }) {
    final call = _toolCalls.putIfAbsent(id, () => _FrbToolCallBuilder());
    call.name = name;
    call.input = input;
  }

  void finish(Map<String, Object?> response) {
    _response = response;
  }

  Map<String, Object?> assistantMessage() {
    final blocks = <Map<String, Object?>>[
      if (_thinking.isNotEmpty)
        <String, Object?>{
          'type': 'thinking',
          'thinking': _thinking.toString(),
          if (_thinkingSignature.isNotEmpty)
            'signature': _thinkingSignature.toString(),
        },
      if (_text.isNotEmpty)
        <String, Object?>{'type': 'text', 'text': _text.toString()},
      for (final call in toolCalls) call.toToolUseBlock(),
    ];
    return <String, Object?>{'role': 'assistant', 'content': blocks};
  }
}

class _FrbToolCallBuilder {
  String name = '';
  Object? input;
  final StringBuffer partialInputJson = StringBuffer();

  _FrbToolCall finish({required String id}) {
    return _FrbToolCall(
      id: id,
      name: name,
      input: input ?? _toolInput(partialInputJson.toString()),
    );
  }
}

class _FrbToolCall {
  const _FrbToolCall({
    required this.id,
    required this.name,
    required this.input,
  });

  final String id;
  final String name;
  final Object? input;

  Map<String, Object?> toToolUseBlock() => <String, Object?>{
    'type': 'tool_use',
    'id': id,
    'name': name,
    'input': input ?? const <String, Object?>{},
  };
}

class _FrbToolResult {
  const _FrbToolResult({
    required this.id,
    required this.name,
    required this.output,
    this.isError = false,
  });

  final String id;
  final String name;
  final Object? output;
  final bool isError;

  Map<String, Object?> toToolResultBlock() => <String, Object?>{
    'type': 'tool_result',
    'tool_use_id': id,
    'content': output is String ? output : jsonEncode(output),
    if (isError) 'is_error': true,
  };
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

Object? _toolInput(Object? value) {
  if (value is String) {
    try {
      return jsonDecode(value);
    } on FormatException {
      return null;
    }
  }
  return value;
}

int _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return 0;
}
