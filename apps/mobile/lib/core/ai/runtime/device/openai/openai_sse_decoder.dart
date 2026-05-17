/// OpenAI Chat Completions SSE → [LlmStreamEvent] decoder.
library;

import 'dart:async';
import 'dart:convert';

import '../llm_stream_event.dart';

class _ToolCallState {
  String id = '';
  String name = '';
  final StringBuffer args = StringBuffer();
  bool started = false;
  bool ended = false;
}

class OpenAiStreamState {
  final Map<int, _ToolCallState> _tools = {};
}

List<LlmStreamEvent> mapOpenAiFrame(OpenAiStreamState state, String frameData) {
  final trimmed = frameData.trim();
  if (trimmed.isEmpty || trimmed == '[DONE]') return const [];

  final Object? decoded;
  try {
    decoded = jsonDecode(frameData);
  } on FormatException {
    return const [];
  }
  if (decoded is! Map) return const [];
  final root = _asMap(decoded);
  final rootError = _asMap(root['error']);
  if (rootError.isNotEmpty) {
    return [
      LlmStreamErrorEvent(
        code: rootError['type'] as String? ?? 'provider_error',
        message: rootError['message'] as String? ?? 'provider stream error',
      ),
    ];
  }

  final events = <LlmStreamEvent>[];
  final choices = root['choices'];
  if (choices is List) {
    for (final rawChoice in choices) {
      final choice = _asMap(rawChoice);
      events.addAll(_mapChoice(state, choice));
    }
  }
  final usage = _usageEvent(root['usage']);
  if (usage != null) events.add(usage);
  return events;
}

List<LlmStreamEvent> _mapChoice(
  OpenAiStreamState state,
  Map<String, Object?> choice,
) {
  final events = <LlmStreamEvent>[];
  final delta = _asMap(choice['delta']);

  final content = delta['content'];
  if (content is String && content.isNotEmpty) {
    events.add(LlmTextDelta(content));
  }
  final reasoning = delta['reasoning_content'] ?? delta['reasoning'];
  if (reasoning is String && reasoning.isNotEmpty) {
    events.add(LlmThinkingDelta(reasoning));
  }

  final toolCalls = delta['tool_calls'];
  if (toolCalls is List) {
    for (final raw in toolCalls) {
      final tc = _asMap(raw);
      final index = _intValue(tc['index']) ?? 0;
      final tool = state._tools.putIfAbsent(index, _ToolCallState.new);
      final id = tc['id'];
      if (id is String && id.isNotEmpty) tool.id = id;
      final fn = _asMap(tc['function']);
      final name = fn['name'];
      if (name is String && name.isNotEmpty) tool.name = name;

      final effectiveId = tool.id.isNotEmpty ? tool.id : 'call_$index';
      if (!tool.started && (tool.id.isNotEmpty || tool.name.isNotEmpty)) {
        tool.started = true;
        events.add(LlmToolCallStart(id: effectiveId, name: tool.name));
      }

      final args = fn['arguments'];
      if (args is String && args.isNotEmpty) {
        tool.args.write(args);
        events.add(LlmToolCallDelta(id: effectiveId, partialInputJson: args));
      }
    }
  }

  final finishReason = choice['finish_reason'] as String?;
  if (finishReason == 'tool_calls' || finishReason == 'function_call') {
    for (final entry
        in state._tools.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key))) {
      final tool = entry.value;
      if (tool.ended) continue;
      final id = tool.id.isNotEmpty ? tool.id : 'call_${entry.key}';
      if (!tool.started) {
        events.add(LlmToolCallStart(id: id, name: tool.name));
      }
      events.add(
        LlmToolCallEnd(
          id: id,
          name: tool.name,
          input: _decodeArgs(tool.args.toString()),
        ),
      );
      tool.ended = true;
    }
    events.add(const LlmMessageStop(LlmStopReason.toolUse));
  } else {
    final reason = openAiStopReason(finishReason);
    if (reason != null) events.add(LlmMessageStop(reason));
  }

  return events;
}

LlmStopReason? openAiStopReason(String? finishReason) => switch (finishReason) {
  'stop' => LlmStopReason.endTurn,
  'length' => LlmStopReason.maxTokens,
  'tool_calls' || 'function_call' => LlmStopReason.toolUse,
  'content_filter' => LlmStopReason.refusal,
  _ => null,
};

Stream<LlmStreamEvent> decodeOpenAiSse(Stream<List<int>> bytes) async* {
  final state = OpenAiStreamState();
  final lines = bytes
      .map<List<int>>((c) => c)
      .transform(utf8.decoder)
      .transform(const LineSplitter());
  final dataBuf = StringBuffer();

  Iterable<LlmStreamEvent> flush() {
    if (dataBuf.isEmpty) return const [];
    final data = dataBuf.toString();
    dataBuf.clear();
    return mapOpenAiFrame(state, data);
  }

  await for (final line in lines) {
    if (line.isEmpty) {
      yield* Stream.fromIterable(flush());
      continue;
    }
    if (line.startsWith(':')) continue;
    if (line.startsWith('data:')) {
      final piece = line.substring(5).trimLeft();
      if (dataBuf.isNotEmpty) dataBuf.write('\n');
      dataBuf.write(piece);
    }
  }
  yield* Stream.fromIterable(flush());
}

LlmUsage? _usageEvent(Object? usage) {
  if (usage is! Map) return null;
  int u(String k) {
    final v = usage[k];
    return v is int ? v : (v is num ? v.toInt() : 0);
  }

  return LlmUsage(
    inputTokens: u('prompt_tokens'),
    outputTokens: u('completion_tokens'),
    cacheReadTokens: 0,
    cacheWriteTokens: 0,
  );
}

Object? _decodeArgs(String args) {
  if (args.trim().isEmpty) return <String, Object?>{};
  try {
    return jsonDecode(args);
  } on FormatException {
    return null;
  }
}

int? _intValue(Object? v) => v is int ? v : (v is num ? v.toInt() : null);

Map<String, Object?> _asMap(Object? v) =>
    v is Map ? v.map((k, val) => MapEntry(k.toString(), val)) : const {};
