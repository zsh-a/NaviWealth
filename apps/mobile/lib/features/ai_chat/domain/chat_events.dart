/// Sealed wire events emitted by `POST /ai/chat`'s SSE stream. See
/// `apps/backend/src/routes/ai.rs` for the producer.
///
/// The relay's tool loop emits these in order: optionally one or more
/// `tool_call` / `tool_result` pairs (per round), zero or more `text`
/// chunks (each round may produce some prose before invoking tools), and
/// finally a single `done` (or `error` then `done`).
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

/// Worker hit a fatal condition (Anthropic 5xx, rate limit exhaustion,
/// auth failure during the loop). A `done` follows.
class ErrorEvent extends AiChatEvent {
  const ErrorEvent(this.message);
  final String message;
}

/// Stream terminator. `stopReason` is Anthropic's verbatim value
/// (`end_turn`, `max_tokens`, `tool_use`, `error`, …); `rounds` is the
/// number of inner Anthropic round-trips the worker performed.
class DoneEvent extends AiChatEvent {
  const DoneEvent({required this.stopReason, required this.rounds});
  final String stopReason;
  final int rounds;
}
