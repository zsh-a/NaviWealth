import 'dart:convert';

import 'chat_events.dart' show TokenUsage;
import 'proposal_apply_state.dart';

/// Roles understood by the chat runtime.
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

/// How an assistant turn finished, mirrored from Anthropic's `stop_reason`
/// (forwarded by the backend in the SSE `done` frame).
///
/// We keep this *ephemeral* — the value lives on [ChatMessage] for the
/// current session only and is intentionally not persisted to Drift. The
/// UI uses it to surface a slim "reply was truncated" footer right after
/// the response lands; once the user moves on (or the session is
/// re-opened later), the message is treated as plain history.
///
///  * [endTurn] — model finished naturally; nothing to flag.
///  * [maxTokens] — output ran into the per-call token budget; the
///    visible text is incomplete.
///  * [toolUse] — backend hit `MAX_TOOL_ROUNDS` while still wanting to
///    call tools; emitted alongside an `error` frame from the backend.
///  * [refusal] — model declined to answer.
///  * [error] — stream ended before `done`, or the backend reported an
///    upstream failure.
///  * [unknown] — anything else, surfaced for forward compat so we don't
///    silently swallow new Anthropic stop reasons.
enum ChatStopReason { endTurn, maxTokens, toolUse, refusal, error, unknown }

extension ChatStopReasonX on ChatStopReason {
  /// `true` when the user should be told the reply may be incomplete.
  /// `endTurn` is the only "all good" outcome.
  bool get isAbnormal => this != ChatStopReason.endTurn;

  static ChatStopReason parse(String? wire) => switch (wire) {
    'end_turn' => ChatStopReason.endTurn,
    'max_tokens' => ChatStopReason.maxTokens,
    'tool_use' => ChatStopReason.toolUse,
    'refusal' || 'stop_sequence' => ChatStopReason.refusal,
    'error' => ChatStopReason.error,
    null => ChatStopReason.unknown,
    _ => ChatStopReason.unknown,
  };
}

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
    this.applyState,
    this.partialInputJson,
  });

  final String id;
  final String name;
  final Object? input;
  final Object? output;
  final String? partialInputJson;

  /// FIR-67 — apply state for `propose_*` tool calls. `null` for read-only
  /// tools and for propose tools the user hasn't acted on yet (the UI
  /// treats null and `pending` identically; null keeps the JSON payload
  /// quiet for non-propose calls so we don't bloat persisted history).
  final ProposalApplyState? applyState;

  ToolInvocation copyWith({
    String? name,
    Object? input,
    Object? output,
    String? partialInputJson,
    ProposalApplyState? applyState,
    bool clearApplyState = false,
  }) => ToolInvocation(
    id: id,
    name: name ?? this.name,
    input: input ?? this.input,
    output: output ?? this.output,
    partialInputJson: partialInputJson ?? this.partialInputJson,
    applyState: clearApplyState ? null : (applyState ?? this.applyState),
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'input': input,
    if (partialInputJson != null) 'partial_input_json': partialInputJson,
    'output': output,
    if (applyState != null) 'apply_state': applyState!.toJson(),
  };

  factory ToolInvocation.fromJson(Map<String, Object?> json) {
    final raw = json['apply_state'];
    final apply = raw is Map
        ? ProposalApplyState.fromJson(
            raw.map((k, v) => MapEntry(k.toString(), v)),
          )
        : null;
    return ToolInvocation(
      id: (json['id'] ?? '') as String,
      name: (json['name'] ?? '') as String,
      input: json['input'],
      output: json['output'],
      partialInputJson: json['partial_input_json'] as String?,
      applyState: apply,
    );
  }

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
///
/// [stopReason] is set by the repository when the SSE stream finishes
/// (or aborts) and consumed by the UI to render a truncation footer.
/// It rides along with the message in Drift so the affordance survives
/// app restarts; old rows from before the column existed read as
/// `null`, in which case the UI shows the message as a clean reply.
///
/// [textSegments] preserves the temporal interleaving between text and
/// tool blocks emitted by the model — segment 0 is the prose before
/// `toolCalls[0]`, segment 1 sits between `toolCalls[0]` and
/// `toolCalls[1]`, and so on. The invariant
/// `textSegments.length == toolCalls.length + 1` holds for every turn
/// recorded by the current repository; legacy rows persist with an
/// empty list and fall back through [displaySegments] to a single
/// trailing segment carrying [content] (matching the pre-FIR layout
/// where prose rendered after all tool cards).
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
    this.textSegments = const <String>[],
    this.errorMessage,
    this.stopReason,
    this.reasoningText,
    this.usage,
  });

  final String id;
  final String sessionId;
  final String ownerUserId;
  final ChatRole role;

  /// Flattened text of the assistant turn — the join of [textSegments].
  /// Kept as a stored field so legacy callers (LLM replay, free-text
  /// search) keep working without touching every site.
  final String content;
  final List<ToolInvocation> toolCalls;

  /// Ordered prose blocks, dense between tool calls. Empty for messages
  /// recorded before this field existed; consumers should read
  /// [displaySegments] which normalises both shapes.
  final List<String> textSegments;
  final ChatMessageStatus status;
  final String? errorMessage;
  final ChatStopReason? stopReason;
  final String? reasoningText;
  final TokenUsage? usage;
  final DateTime createdAt;

  /// Render-ready segment list. Always returns
  /// `toolCalls.length + 1` entries:
  ///
  ///  * Modern messages return [textSegments] verbatim.
  ///  * Legacy / inconsistent rows (where the lengths don't line up)
  ///    fall back to "all empty preceding segments + [content] in the
  ///    trailing slot", which collapses to the pre-segment layout
  ///    where prose appeared once *after* every tool card.
  List<String> get displaySegments {
    final expected = toolCalls.length + 1;
    if (textSegments.length == expected) return textSegments;
    return <String>[for (var i = 0; i < expected - 1; i++) '', content];
  }

  ChatMessage copyWith({
    String? content,
    List<ToolInvocation>? toolCalls,
    List<String>? textSegments,
    ChatMessageStatus? status,
    String? errorMessage,
    ChatStopReason? stopReason,
    String? reasoningText,
    TokenUsage? usage,
  }) => ChatMessage(
    id: id,
    sessionId: sessionId,
    ownerUserId: ownerUserId,
    role: role,
    content: content ?? this.content,
    toolCalls: toolCalls ?? this.toolCalls,
    textSegments: textSegments ?? this.textSegments,
    status: status ?? this.status,
    errorMessage: errorMessage ?? this.errorMessage,
    stopReason: stopReason ?? this.stopReason,
    reasoningText: reasoningText ?? this.reasoningText,
    usage: usage ?? this.usage,
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
