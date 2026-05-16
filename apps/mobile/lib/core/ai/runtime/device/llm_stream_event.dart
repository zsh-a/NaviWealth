/// Provider-neutral low-level stream events emitted by a device LLM
/// adapter (§4.6 W-D2).
///
/// This is the Dart mirror of the backend `AgentEvent` subset that the
/// Anthropic adapter produces (`apps/backend/src/ai/runtime/event.rs` /
/// `adapters/anthropic/event_map.rs`). The W-D3 device agent loop
/// consumes this stream and translates it into the existing
/// [AiChatEvent] taxonomy (`features/ai_chat/domain/chat_events.dart`)
/// so the chat UI / proposal applier / trace builder stay unchanged.
///
/// Kept provider-neutral (not Anthropic-specific) so a future
/// OpenAI-compatible adapter can emit the same stream.
library;

/// Why the model ended a single message. Mirrors backend
/// `StopReason`; unknown provider values yield *no* stop event (the
/// loop only acts on the four it understands), so there is no
/// `unknown` member by design.
enum LlmStopReason {
  endTurn,
  maxTokens,
  toolUse,
  refusal;

  /// Anthropic `stop_reason` → enum. Returns null for anything else,
  /// matching the backend `stop_reason()` `and_then` filter.
  static LlmStopReason? tryParse(String? s) => switch (s) {
    'end_turn' => LlmStopReason.endTurn,
    'max_tokens' => LlmStopReason.maxTokens,
    'tool_use' => LlmStopReason.toolUse,
    'refusal' => LlmStopReason.refusal,
    _ => null,
  };

  /// Verbatim Anthropic wire value — the existing [DoneEvent.stopReason]
  /// contract is the raw provider string, so the loop re-serialises
  /// through this.
  String get wire => switch (this) {
    LlmStopReason.endTurn => 'end_turn',
    LlmStopReason.maxTokens => 'max_tokens',
    LlmStopReason.toolUse => 'tool_use',
    LlmStopReason.refusal => 'refusal',
  };
}

sealed class LlmStreamEvent {
  const LlmStreamEvent();
}

/// Visible assistant text fragment.
class LlmTextDelta extends LlmStreamEvent {
  const LlmTextDelta(this.text);
  final String text;
}

/// Provider reasoning fragment (folded panel in the UI).
class LlmThinkingDelta extends LlmStreamEvent {
  const LlmThinkingDelta(this.text);
  final String text;
}

/// Model began a `tool_use` block. `name` is known up-front from the
/// `content_block_start` frame.
class LlmToolCallStart extends LlmStreamEvent {
  const LlmToolCallStart({required this.id, required this.name});
  final String id;
  final String name;
}

/// Incremental raw JSON for a tool input. Not parseable until the
/// matching [LlmToolCallEnd] arrives.
class LlmToolCallDelta extends LlmStreamEvent {
  const LlmToolCallDelta({required this.id, required this.partialInputJson});
  final String id;
  final String partialInputJson;
}

/// Tool input fully assembled. Carries `name` (unlike the backend
/// id-only event) so the loop can build an [AiChatEvent] ToolCallEvent
/// directly.
class LlmToolCallEnd extends LlmStreamEvent {
  const LlmToolCallEnd({
    required this.id,
    required this.name,
    required this.input,
  });
  final String id;
  final String name;

  /// Decoded JSON (Map / List / scalar) or `null` if the partial JSON
  /// failed to parse — mirrors the backend `tool_input` fallback.
  final Object? input;
}

/// Provider token accounting. Multiple may arrive per turn
/// (`message_start` then `message_delta`); the loop accumulates.
class LlmUsage extends LlmStreamEvent {
  const LlmUsage({
    required this.inputTokens,
    required this.outputTokens,
    required this.cacheReadTokens,
    required this.cacheWriteTokens,
  });
  final int inputTokens;
  final int outputTokens;
  final int cacheReadTokens;
  final int cacheWriteTokens;
}

/// One message finished with a reason the loop understands. The loop
/// decides whether this is terminal (`endTurn`) or a tool round
/// (`toolUse`).
class LlmMessageStop extends LlmStreamEvent {
  const LlmMessageStop(this.reason);
  final LlmStopReason reason;
}

/// Provider emitted an `error` event inside the stream.
class LlmStreamErrorEvent extends LlmStreamEvent {
  const LlmStreamErrorEvent({required this.code, required this.message});
  final String code;
  final String message;
}
