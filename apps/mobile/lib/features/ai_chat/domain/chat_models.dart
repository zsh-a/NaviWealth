import 'dart:convert';

/// Roles understood by `POST /ai/chat`.
///
/// `system` and `error` are local-only roles the UI uses to surface
/// truncation banners and stream failures; they never get sent back to
/// the model.
enum ChatRole { user, assistant, system, error }

extension ChatRoleX on ChatRole {
  String get wire => switch (this) {
    ChatRole.user => 'user',
    ChatRole.assistant => 'assistant',
    ChatRole.system => 'system',
    ChatRole.error => 'error',
  };

  static ChatRole parse(String s) => switch (s) {
    'user' => ChatRole.user,
    'assistant' => ChatRole.assistant,
    'system' => ChatRole.system,
    'error' => ChatRole.error,
    _ => ChatRole.assistant,
  };
}

/// Lifecycle of a single message row.
///
/// `streaming` is the in-flight assistant turn currently receiving SSE
/// frames; `complete` is a finished turn ready to be re-fed to the model;
/// `errored` is a turn whose stream aborted before `done`.
enum ChatMessageStatus { streaming, complete, errored }

extension ChatMessageStatusX on ChatMessageStatus {
  String get wire => switch (this) {
    ChatMessageStatus.streaming => 'streaming',
    ChatMessageStatus.complete => 'complete',
    ChatMessageStatus.errored => 'errored',
  };

  static ChatMessageStatus parse(String s) => switch (s) {
    'streaming' => ChatMessageStatus.streaming,
    'complete' => ChatMessageStatus.complete,
    'errored' => ChatMessageStatus.errored,
    _ => ChatMessageStatus.complete,
  };
}

/// A single tool invocation within an assistant turn.
///
/// `input` is whatever JSON the model sent as the tool's arguments.
/// `output` is the tool's structured return value (filled in once the
/// `tool_result` SSE frame arrives). The pair is rendered as a
/// collapsible chip under the assistant message so the user can see
/// "我查了你最近 3 个月的交易".
class ToolInvocation {
  const ToolInvocation({
    required this.id,
    required this.name,
    required this.input,
    this.output,
  });

  final String id;
  final String name;
  final Object? input;
  final Object? output;

  ToolInvocation copyWith({Object? output}) =>
      ToolInvocation(id: id, name: name, input: input, output: output);

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'input': input,
    'output': output,
  };

  factory ToolInvocation.fromJson(Map<String, Object?> json) => ToolInvocation(
    id: (json['id'] ?? '') as String,
    name: (json['name'] ?? '') as String,
    input: json['input'],
    output: json['output'],
  );

  static String encodeList(List<ToolInvocation> items) =>
      jsonEncode(items.map((t) => t.toJson()).toList());

  static List<ToolInvocation> decodeList(String? raw) {
    if (raw == null || raw.isEmpty) return const <ToolInvocation>[];
    final parsed = jsonDecode(raw);
    if (parsed is! List) return const <ToolInvocation>[];
    return parsed
        .whereType<Map<Object?, Object?>>()
        .map(
          (m) => ToolInvocation.fromJson(
            m.map((k, v) => MapEntry(k.toString(), v)),
          ),
        )
        .toList(growable: false);
  }
}

/// One persisted turn in a [ChatSession].
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.sessionId,
    required this.ownerUserId,
    required this.role,
    required this.content,
    required this.status,
    required this.createdAt,
    this.toolCalls = const <ToolInvocation>[],
    this.errorMessage,
  });

  final String id;
  final String sessionId;
  final String ownerUserId;
  final ChatRole role;
  final String content;
  final List<ToolInvocation> toolCalls;
  final ChatMessageStatus status;
  final String? errorMessage;
  final DateTime createdAt;

  ChatMessage copyWith({
    String? content,
    List<ToolInvocation>? toolCalls,
    ChatMessageStatus? status,
    String? errorMessage,
  }) => ChatMessage(
    id: id,
    sessionId: sessionId,
    ownerUserId: ownerUserId,
    role: role,
    content: content ?? this.content,
    toolCalls: toolCalls ?? this.toolCalls,
    status: status ?? this.status,
    errorMessage: errorMessage ?? this.errorMessage,
    createdAt: createdAt,
  );
}

/// One AI conversation thread shown in the sidebar.
class ChatSession {
  const ChatSession({
    required this.id,
    required this.ownerUserId,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.lastMessageAt,
    this.model,
  });

  final String id;
  final String ownerUserId;
  final String title;
  final String? model;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastMessageAt;
}
