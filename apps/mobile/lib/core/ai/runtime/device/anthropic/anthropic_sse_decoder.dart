/// Anthropic SSE → [LlmStreamEvent] decoder.
///
/// Faithful Dart port of
/// the historical backend Anthropic event-map. The backend
/// buffers the whole body then maps; on device we stream incrementally
/// for progressive rendering. [mapAnthropicFrame] mirrors
/// `map_sse_frame` 1:1 for frame-level parity tests.
///
/// **Deliberate divergence**: a malformed/non-JSON frame is skipped
/// (yields no events) rather than failing the whole stream. The Rust
/// path returns `Err`; on a long device turn a single bad keepalive or
/// comment frame must not kill the conversation. Documented here and in
/// the parity test.
library;

import 'dart:async';
import 'dart:convert';

import '../llm_stream_event.dart';

/// Per-content-block accumulation state, keyed by Anthropic block index.
class _BlockState {
  _BlockState({this.type = '', this.id, this.name, this.input});
  String type;
  String? id;
  String? name;
  Object? input;
  final StringBuffer inputJson = StringBuffer();
}

/// Mutable stream state threaded across frames within one message.
class AnthropicStreamState {
  final Map<int, _BlockState> _blocks = {};
}

/// Map one SSE `data:` payload to zero or more events, mutating
/// [state]. Mirrors `map_sse_frame`.
List<LlmStreamEvent> mapAnthropicFrame(
  AnthropicStreamState state,
  String frameData,
) {
  final trimmed = frameData.trim();
  if (trimmed.isEmpty || trimmed == '[DONE]') return const [];

  Object? decoded;
  try {
    decoded = jsonDecode(frameData);
  } on FormatException {
    return const []; // see library doc — skip, don't kill the stream
  }
  if (decoded is! Map) return const [];
  final event = decoded.map((k, v) => MapEntry(k.toString(), v));
  final type = event['type'];

  switch (type) {
    case 'message_start':
      final usage = _pointer(event, ['message', 'usage']);
      final u = _usageEvent(usage);
      return u == null ? const [] : [u];
    case 'content_block_start':
      return _mapContentBlockStart(state, event);
    case 'content_block_delta':
      return _mapContentBlockDelta(state, event);
    case 'content_block_stop':
      return _mapContentBlockStop(state, event);
    case 'message_delta':
      return _mapMessageDelta(event);
    case 'error':
      return [_mapError(event)];
    case 'message_stop':
    case 'ping':
    default:
      return const [];
  }
}

List<LlmStreamEvent> _mapContentBlockStart(
  AnthropicStreamState state,
  Map<String, Object?> event,
) {
  final index = _eventIndex(event);
  final block = _asMap(event['content_block']);
  final type = block['type'] as String? ?? '';
  final id = block['id'] as String?;
  final name = block['name'] as String?;

  state._blocks[index] = _BlockState(
    type: type,
    id: id,
    name: name,
    input: block['input'],
  );

  switch (type) {
    case 'text':
      final text = block['text'];
      if (text is String && text.isNotEmpty) return [LlmTextDelta(text)];
      return const [];
    case 'thinking':
      final out = <LlmStreamEvent>[];
      final text = block['thinking'];
      if (text is String && text.isNotEmpty) out.add(LlmThinkingDelta(text));
      // Some Anthropic-compatible gateways inline the signature on the
      // start frame rather than streaming a `signature_delta`.
      final sig = block['signature'];
      if (sig is String && sig.isNotEmpty) {
        out.add(LlmThinkingSignatureDelta(sig));
      }
      return out;
    case 'tool_use':
      return [LlmToolCallStart(id: id ?? '', name: name ?? '')];
    default:
      return const [];
  }
}

List<LlmStreamEvent> _mapContentBlockDelta(
  AnthropicStreamState state,
  Map<String, Object?> event,
) {
  final index = _eventIndex(event);
  final delta = _asMap(event['delta']);

  switch (delta['type']) {
    case 'text_delta':
      final text = delta['text'];
      return text is String ? [LlmTextDelta(text)] : const [];
    case 'thinking_delta':
      final text = delta['thinking'];
      return text is String ? [LlmThinkingDelta(text)] : const [];
    case 'signature_delta':
      // Opaque reasoning signature — not rendered, but must survive
      // into the assistant turn so subsequent tool rounds don't get
      // rejected for a dropped `thinking` block.
      final sig = delta['signature'];
      return sig is String && sig.isNotEmpty
          ? [LlmThinkingSignatureDelta(sig)]
          : const [];
    case 'input_json_delta':
      final partial = delta['partial_json'] as String? ?? '';
      final block = state._blocks.putIfAbsent(index, _BlockState.new);
      block.inputJson.write(partial);
      return [LlmToolCallDelta(id: block.id ?? '', partialInputJson: partial)];
    default:
      return const [];
  }
}

List<LlmStreamEvent> _mapContentBlockStop(
  AnthropicStreamState state,
  Map<String, Object?> event,
) {
  final index = _eventIndex(event);
  final block = state._blocks.remove(index);
  if (block == null || block.type != 'tool_use') return const [];
  return [
    LlmToolCallEnd(
      id: block.id ?? '',
      name: block.name ?? '',
      input: _toolInput(block.input, block.inputJson.toString()),
    ),
  ];
}

List<LlmStreamEvent> _mapMessageDelta(Map<String, Object?> event) {
  final events = <LlmStreamEvent>[];
  final usage = _usageEvent(event['usage']);
  if (usage != null) events.add(usage);
  final reason = LlmStopReason.tryParse(
    _pointer(event, ['delta', 'stop_reason']) as String?,
  );
  if (reason != null) events.add(LlmMessageStop(reason));
  return events;
}

LlmStreamEvent _mapError(Map<String, Object?> event) {
  final error = _asMap(event['error']);
  return LlmStreamErrorEvent(
    code: error['type'] as String? ?? 'provider_error',
    message: error['message'] as String? ?? 'provider stream error',
  );
}

LlmUsage? _usageEvent(Object? usage) {
  if (usage is! Map) return null;
  int u(String k) {
    final v = usage[k];
    return v is int ? v : (v is num ? v.toInt() : 0);
  }

  return LlmUsage(
    inputTokens: u('input_tokens'),
    outputTokens: u('output_tokens'),
    cacheReadTokens: u('cache_read_input_tokens'),
    cacheWriteTokens: u('cache_creation_input_tokens'),
  );
}

/// `partial_json` empty ⇒ the `content_block_start` `input` (or `{}`);
/// otherwise parse it, falling back to `null` on a parse failure —
/// mirrors `tool_input`.
Object? _toolInput(Object? initial, String partialJson) {
  if (partialJson.trim().isEmpty) {
    return initial ?? <String, Object?>{};
  }
  try {
    return jsonDecode(partialJson);
  } on FormatException {
    return null;
  }
}

int _eventIndex(Map<String, Object?> event) {
  final v = event['index'];
  return v is int ? v : (v is num ? v.toInt() : 0);
}

Map<String, Object?> _asMap(Object? v) =>
    v is Map ? v.map((k, val) => MapEntry(k.toString(), val)) : const {};

Object? _pointer(Map<String, Object?> root, List<String> path) {
  Object? cur = root;
  for (final key in path) {
    if (cur is! Map) return null;
    cur = cur[key];
  }
  return cur;
}

/// Stream the raw SSE byte stream into [LlmStreamEvent]s.
///
/// Framing: UTF-8 decode across chunk boundaries, blank line ends a
/// frame, `data:` lines accumulate (joined with `\n`), `:` comment /
/// keepalive lines are skipped. The `event:` line is ignored — the JSON
/// payload's own `type` drives [mapAnthropicFrame], exactly like the
/// historical backend `sse_data_frames`.
Stream<LlmStreamEvent> decodeAnthropicSse(Stream<List<int>> bytes) async* {
  final state = AnthropicStreamState();
  final lines = bytes
      .map<List<int>>((c) => c)
      .transform(utf8.decoder)
      .transform(const LineSplitter());
  final dataBuf = StringBuffer();

  Iterable<LlmStreamEvent> flush() {
    if (dataBuf.isEmpty) return const [];
    final data = dataBuf.toString();
    dataBuf.clear();
    return mapAnthropicFrame(state, data);
  }

  await for (final line in lines) {
    if (line.isEmpty) {
      yield* Stream.fromIterable(flush());
      continue;
    }
    if (line.startsWith(':')) continue; // comment / keepalive
    if (line.startsWith('data:')) {
      final piece = line.substring(5).trimLeft();
      if (dataBuf.isNotEmpty) dataBuf.write('\n');
      dataBuf.write(piece);
    }
    // `event:` / `id:` / `retry:` ignored — JSON `type` is authoritative.
  }
  // Trailing frame with no terminating blank line.
  yield* Stream.fromIterable(flush());
}
