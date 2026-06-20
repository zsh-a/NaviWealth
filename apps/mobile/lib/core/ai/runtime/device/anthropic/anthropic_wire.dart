/// Anthropic Messages API wire types.
///
/// Dart mirror of the historical backend Anthropic wire types,
/// plus content-block builders the device loop and on-device
/// Vision ingest need. snake_case JSON per §10, even though
/// these requests never touch our servers.
library;

import 'dart:convert';

/// Default model when the request doesn't override it.
///
/// The backend default is a ModelScope gateway model; the device path
/// uses the user's own Anthropic key, so default to a current Claude
/// assistant model (cost/quality balance for routine chat — the user
/// can override later).
const String kDefaultDeviceModel = 'claude-sonnet-4-6';

/// One Messages API message. `role` is `user` or `assistant`; system
/// instructions ride on [AnthropicRequest.system]. `content` is either
/// a plain string or a list of typed blocks (`text` / `tool_use` /
/// `tool_result` / `image`).
class AnthropicChatMessage {
  const AnthropicChatMessage({required this.role, required this.content});

  /// Convenience for a plain-text user/assistant turn.
  factory AnthropicChatMessage.text(String role, String text) =>
      AnthropicChatMessage(role: role, content: text);

  final String role;
  final Object? content;

  Map<String, Object?> toJson() => {'role': role, 'content': content};

  static AnthropicChatMessage fromJson(Map<String, Object?> json) =>
      AnthropicChatMessage(
        role: json['role'] as String? ?? 'user',
        content: json['content'],
      );
}

/// Tool schema as Anthropic expects it. `inputSchema` is a JSON Schema
/// object (ported verbatim from the backend tool registry).
class AnthropicToolSchema {
  const AnthropicToolSchema({
    required this.name,
    required this.description,
    required this.inputSchema,
  });

  final String name;
  final String description;
  final Map<String, Object?> inputSchema;

  Map<String, Object?> toJson() => {
    'name': name,
    'description': description,
    'input_schema': inputSchema,
  };
}

class AnthropicRequest {
  const AnthropicRequest({
    required this.model,
    required this.maxTokens,
    required this.system,
    required this.messages,
    this.tools = const [],
    this.stream = true,
  });

  final String model;
  final int maxTokens;
  final String system;
  final List<AnthropicChatMessage> messages;
  final List<AnthropicToolSchema> tools;
  final bool stream;

  Map<String, Object?> toJson() => {
    'model': model,
    'max_tokens': maxTokens,
    'system': system,
    'messages': messages.map((m) => m.toJson()).toList(),
    'tools': tools.map((t) => t.toJson()).toList(),
    'stream': stream,
  };

  /// Body for the streaming call — `stream` forced true (mirrors the
  /// backend `serialize_streaming_payload`).
  String encodeStreaming() => jsonEncode({...toJson(), 'stream': true});

  /// Body for the one-shot Vision/ingest call — `stream` forced false
  /// (mirrors the backend `complete`).
  String encodeOneShot() => jsonEncode({...toJson(), 'stream': false});
}

/// Content-block builders. The model emits `text` / `tool_use`; we send
/// back `tool_result`, and `image` for the Vision path.
abstract final class AnthropicBlocks {
  static Map<String, Object?> text(String value) => {
    'type': 'text',
    'text': value,
  };

  /// Assistant `thinking` block, re-sent verbatim on every subsequent
  /// tool round. Providers that emit reasoning (native Anthropic
  /// extended thinking, MiMo thinking mode, …) **reject** a follow-up
  /// request whose tool-calling assistant turn dropped this block, so
  /// the device loop reconstructs it from the streamed reasoning. The
  /// `signature` is included only when the provider supplied one
  /// (native Anthropic requires it; reasoning-only providers omit it).
  static Map<String, Object?> thinking({
    required String thinking,
    String? signature,
  }) => {
    'type': 'thinking',
    'thinking': thinking,
    if (signature != null && signature.isNotEmpty) 'signature': signature,
  };

  /// `tool_result` block fed back into the next user turn. `content` is
  /// the tool's JSON-encoded output string (Anthropic accepts a string
  /// or a block list; the loop sends a string).
  static Map<String, Object?> toolResult({
    required String toolUseId,
    required String content,
    bool isError = false,
  }) => {
    'type': 'tool_result',
    'tool_use_id': toolUseId,
    'content': content,
    if (isError) 'is_error': true,
  };

  /// base64 image block for on-device Vision ingest. The raw
  /// image never leaves the device except directly to the user's
  /// provider.
  static Map<String, Object?> imageBase64({
    required String mediaType,
    required String data,
  }) => {
    'type': 'image',
    'source': {'type': 'base64', 'media_type': mediaType, 'data': data},
  };
}
