library;

import 'dart:convert';

import 'package:naviwealth/app/agent_runtime/tools/agent_runtime_tool_dispatcher.dart';
import 'package:naviwealth/core/ai/contracts/contracts.dart';
import 'package:naviwealth/core/ai/runtime/agent_runtime/agent_runtime_json.dart';

class FrbStreamRoundState {
  FrbStreamRoundState({required this.inputMessageCount});

  final int inputMessageCount;
  final StringBuffer _text = StringBuffer();
  final StringBuffer _thinking = StringBuffer();
  final StringBuffer _thinkingSignature = StringBuffer();
  final Map<String, FrbToolCallBuilder> _toolCalls =
      <String, FrbToolCallBuilder>{};
  Map<String, Object?> _response = const <String, Object?>{};
  Map<String, Object?> _finishMetadata = const <String, Object?>{};
  TokenUsage? _usage;
  String? _doneStopReason;

  bool get emittedText => _text.isNotEmpty;

  String get text => _text.toString();

  Map<String, Object?> get response => _response;

  String get status => frbString(_finishMetadata['status']);

  Map<String, Object?>? get chatState =>
      frbObjectOrNull(_finishMetadata['chat_state']);

  Map<String, Object?>? get chatSnapshot =>
      frbObjectOrNull(_finishMetadata['chat_snapshot']);

  String? get doneStopReason => _doneStopReason;

  TokenUsage? get usage => _usage ?? frbUsageFromResponse(_response);

  String get stopReason =>
      frbChatStopReason(frbString(_response['finish_reason']));

  List<AgentRuntimeToolCall> get toolCalls {
    return [
      for (final entry in _toolCalls.entries) entry.value.finish(id: entry.key),
    ];
  }

  List<AgentRuntimeToolCall> get requiredToolCalls {
    final calls = _finishMetadata['tool_calls'];
    if (calls is List) {
      final parsed =
          [
                for (final value in calls)
                  if (frbObjectOrNull(value) case final object?)
                    AgentRuntimeToolCall(
                      id: frbString(object['id']),
                      name: frbString(object['name']),
                      input: object['input'],
                    ),
              ]
              .where((call) => call.stringId.isNotEmpty && call.name.isNotEmpty)
              .toList();
      if (parsed.isNotEmpty) return parsed;
    }
    return toolCalls;
  }

  void appendText(String text) => _text.write(text);

  void appendThinking(String text) => _thinking.write(text);

  void appendThinkingSignature(String value) {
    if (value.isNotEmpty) _thinkingSignature.write(value);
  }

  void startToolCall({required String id, required String name}) {
    _toolCalls.putIfAbsent(id, () => FrbToolCallBuilder()).name = name;
  }

  void appendToolInput({required String id, required String partialInputJson}) {
    _toolCalls
        .putIfAbsent(id, () => FrbToolCallBuilder())
        .partialInputJson
        .write(partialInputJson);
  }

  void finishToolCall({
    required String id,
    required String name,
    required Object? input,
  }) {
    final call = _toolCalls.putIfAbsent(id, () => FrbToolCallBuilder());
    call.name = name;
    call.input = input;
  }

  void finish(
    Map<String, Object?> response, {
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    _response = response;
    _finishMetadata = metadata;
    _usage ??= frbUsageFromResponse(response);
  }

  void finishDone(Map<String, Object?> metadata) {
    final stopReason = frbString(metadata['stop_reason']);
    if (stopReason.isNotEmpty) _doneStopReason = stopReason;
  }

  void recordUsage(TokenUsage usage) {
    _usage = usage;
  }
}

class FrbToolCallBuilder {
  String name = '';
  Object? input;
  final StringBuffer partialInputJson = StringBuffer();

  AgentRuntimeToolCall finish({required String id}) {
    return AgentRuntimeToolCall(
      id: id,
      name: name,
      input: input ?? frbToolInput(partialInputJson.toString()),
    );
  }
}

TokenUsage? frbUsageFromResponse(Map<String, Object?> response) {
  return frbUsageFromValue(response['usage']);
}

TokenUsage? frbUsageFromValue(Object? usage) {
  if (usage is! Map) return null;
  return TokenUsage(
    input: frbInt(usage['input_tokens'] ?? usage['input']),
    output: frbInt(usage['output_tokens'] ?? usage['output']),
    cacheRead: frbInt(usage['cache_read_tokens'] ?? usage['cache_read']),
    cacheWrite: frbInt(usage['cache_write_tokens'] ?? usage['cache_write']),
  );
}

String frbChatStopReason(String reason) {
  return switch (reason) {
    'stop' => 'end_turn',
    'length' => 'max_tokens',
    'tool_call' || 'tool_calls' || 'tool_use' => 'tool_use',
    'content_filter' => 'refusal',
    'requires_interaction' => 'requires_interaction',
    'error' => 'error',
    _ when reason.isNotEmpty => reason,
    _ => 'unknown',
  };
}

String frbString(Object? value) => agentRuntimeString(value);

Map<String, Object?> frbObject(Object? value) {
  return frbObjectOrNull(value) ?? const <String, Object?>{};
}

Map<String, Object?>? frbObjectOrNull(Object? value) =>
    agentRuntimeObjectOrNull(value);

Object? frbToolInput(Object? value) {
  if (value is String) {
    try {
      return jsonDecode(value);
    } on FormatException {
      return null;
    }
  }
  return value;
}

int frbInt(Object? value) => agentRuntimeInt(value);

String frbClip(String value, [int max = 500]) {
  if (value.length <= max) return value;
  return '${value.substring(0, max)}...';
}
