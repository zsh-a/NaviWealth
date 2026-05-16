/// Sealed wire events emitted by `POST /ai/chat`'s SSE stream. See
/// `apps/backend/src/routes/ai.rs` for the producer.
///
/// v1 streams emit `text` / `tool_call` / `tool_result` / `error` /
/// `done`. v2 streams emit token-level `text_delta`, optional
/// `thinking_delta`, tool-call construction events, `usage`, and
/// terminal `stop`.
library;

import '../../../core/ai/contracts/contracts.dart' show Freshness;

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

  /// Lazily extracted from `output.freshness` for tools backed by an
  /// AI Read Model. Returns null for legacy tools that don't carry
  /// freshness metadata. Derived so manually-constructed events in
  /// tests automatically expose the field without a separate setter.
  Freshness? get freshness => Freshness.tryFromOutput(output);
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

/// Stream terminator. `stopReason` is Anthropic's verbatim value
/// (`end_turn`, `max_tokens`, `tool_use`, `error`, …); `rounds` is the
/// number of inner Anthropic round-trips the worker performed.
class DoneEvent extends AiChatEvent {
  const DoneEvent({required this.stopReason, required this.rounds});
  final String stopReason;
  final int rounds;
}
