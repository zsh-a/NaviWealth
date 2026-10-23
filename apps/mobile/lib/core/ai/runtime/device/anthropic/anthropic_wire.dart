/// Anthropic message wire shape used by on-device Vision ingest.
library;

/// One Messages API message. `role` is `user` or `assistant`; system
/// instructions are supplied separately. `content` is either
/// a plain string or a list of typed blocks (`text` / `tool_use` /
/// `tool_result` / `image`).
class AnthropicChatMessage {
  const AnthropicChatMessage({required this.role, required this.content});

  final String role;
  final Object? content;

  Map<String, Object?> toJson() => {'role': role, 'content': content};
}
