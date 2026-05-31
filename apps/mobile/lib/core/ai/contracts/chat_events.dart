/// Sealed events emitted by the active device runtime.
///
/// Previously these mirrored `/ai/chat` SSE frames. The cloud route is
/// gone, but the repository/UI contract intentionally keeps the same
/// event vocabulary: text deltas, optional thinking deltas, tool-call
/// construction, tool results, usage, spans, error, and done.
library;

import 'contracts.dart' show AiSpanKind, AiSpanStatus, SpanTokens;

sealed class AiChatEvent {
  const AiChatEvent();
}

/// Model sent a `tool_use` block this round; the worker is about to
/// execute it.
class ToolCallEvent extends AiChatEvent {
  const ToolCallEvent({
    required this.id,
    required this.name,
    required this.input,
  });

  final String id;
  final String name;
  final Object? input;
}

/// v2: the model started constructing a tool call but has not yet
/// produced the final input JSON.
class ToolCallStartEvent extends AiChatEvent {
  const ToolCallStartEvent({required this.id, required this.name});

  final String id;
  final String name;
}

/// v2: incremental raw JSON preview for a tool input. The value may not
/// parse as JSON until the matching [ToolCallEvent] arrives.
class ToolCallDeltaEvent extends AiChatEvent {
  const ToolCallDeltaEvent({required this.id, required this.partialInputJson});

  final String id;
  final String partialInputJson;
}

/// Worker dispatched the tool and returned its output to the model.
class ToolResultEvent extends AiChatEvent {
  const ToolResultEvent({
    required this.id,
    required this.name,
    required this.output,
  });

  final String id;
  final String name;
  final Object? output;
}

/// Anthropic emitted a text block in this round. Multiple frames may
/// arrive across rounds; concatenate them in order to form the final
/// assistant turn body.
class TextEvent extends AiChatEvent {
  const TextEvent(this.text);
  final String text;
}

/// v2 provider reasoning delta. Kept separate from visible assistant
/// text so the UI can render it in a folded reasoning panel.
class ThinkingDeltaEvent extends AiChatEvent {
  const ThinkingDeltaEvent(this.text);
  final String text;
}

class TokenUsage {
  const TokenUsage({
    required this.input,
    required this.output,
    required this.cacheRead,
    required this.cacheWrite,
  });

  final int input;
  final int output;
  final int cacheRead;
  final int cacheWrite;

  int get total => input + output + cacheRead + cacheWrite;

  Map<String, Object?> toJson() => <String, Object?>{
    'input': input,
    'output': output,
    'cache_read': cacheRead,
    'cache_write': cacheWrite,
  };

  factory TokenUsage.fromJson(Map<String, Object?> json) => TokenUsage(
    input: _readInt(json['input']),
    output: _readInt(json['output']),
    cacheRead: _readInt(json['cache_read']),
    cacheWrite: _readInt(json['cache_write']),
  );

  static int _readInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return 0;
  }
}

/// v2 provider token accounting for the current assistant turn.
class UsageEvent extends AiChatEvent {
  const UsageEvent(this.usage);
  final TokenUsage usage;
}

/// Worker hit a fatal condition (Anthropic 5xx, rate limit exhaustion,
/// auth failure during the loop). A `done` follows.
class ErrorEvent extends AiChatEvent {
  const ErrorEvent(this.message, {this.code});
  final String message;
  final String? code;
}

/// Observability-only frame: one finished execution span (an LLM
/// round or a tool dispatch). **Additive** — emitted by
/// `DeviceAgentLoop` after the unit completes, consumed solely by the
/// trace builder. Message-state consumers ignore it (it never mutates
/// the assistant turn). Carries absolute wall-clock `startedAt` /
/// `endedAt`; `AiTraceBuilder` anchors them to the trace start to get
/// the waterfall offset.
class SpanEvent extends AiChatEvent {
  const SpanEvent({
    required this.id,
    this.parentId,
    required this.kind,
    required this.name,
    required this.startedAt,
    required this.endedAt,
    this.status = AiSpanStatus.ok,
    this.errorCode,
    this.errorMessage,
    this.tokens,
    this.model,
    this.stopReason,
    this.input,
    this.output,
    this.attributes,
  });

  final String id;
  final String? parentId;
  final AiSpanKind kind;
  final String name;
  final DateTime startedAt;
  final DateTime endedAt;
  final AiSpanStatus status;
  final String? errorCode;
  final String? errorMessage;
  final SpanTokens? tokens;
  final String? model;
  final String? stopReason;
  final Object? input;
  final Object? output;
  final Map<String, Object?>? attributes;
}

/// Stream terminator. `stopReason` is Anthropic's verbatim value
/// (`end_turn`, `max_tokens`, `tool_use`, `error`, …); `rounds` is the
/// number of inner Anthropic round-trips the worker performed.
class DoneEvent extends AiChatEvent {
  const DoneEvent({required this.stopReason, required this.rounds});
  final String stopReason;
  final int rounds;
}
