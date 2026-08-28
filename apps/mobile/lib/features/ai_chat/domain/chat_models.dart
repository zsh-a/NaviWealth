import 'dart:convert';

import '../../../core/ai/composition/proposal_apply_state.dart';
import '../../../core/ai/contracts/interaction.dart';
import '../../../core/ai/progress/long_task_progress.dart';
import 'chat_events.dart' show TokenUsage;

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

enum ToolInvocationStatus { streamingInput, pendingResult, completed }

extension ToolInvocationStatusX on ToolInvocationStatus {
  bool get isPending => this != ToolInvocationStatus.completed;

  String get wire => switch (this) {
    ToolInvocationStatus.streamingInput => 'streaming_input',
    ToolInvocationStatus.pendingResult => 'pending_result',
    ToolInvocationStatus.completed => 'completed',
  };

  static ToolInvocationStatus parse(String? wire) => switch (wire) {
    'streaming_input' => ToolInvocationStatus.streamingInput,
    'pending_result' => ToolInvocationStatus.pendingResult,
    'completed' => ToolInvocationStatus.completed,
    _ => ToolInvocationStatus.completed,
  };
}

/// How an assistant turn finished, mirrored from Anthropic's `stop_reason`
/// (forwarded by the backend in the SSE `done` frame).
///
/// The value is persisted with [ChatMessage] so an interrupted reply remains
/// diagnosable after reopening the session. The UI uses it to surface a slim
/// recovery footer without mixing transport notices into the model transcript.
///
///  * [endTurn] — model finished naturally; nothing to flag.
///  * [maxTokens] — output ran into the per-call token budget; the
///    visible text is incomplete.
///  * [toolUse] — backend hit `MAX_TOOL_ROUNDS` while still wanting to
///    call tools; emitted alongside an `error` frame from the backend.
///  * [requiresInteraction] — the turn is paused at a pending human
///    interaction; the interaction card owns the next action.
///  * [refusal] — model declined to answer.
///  * [error] — stream ended before `done`, or the backend reported an
///    upstream failure.
///  * [unknown] — anything else, surfaced for forward compat so we don't
///    silently swallow new Anthropic stop reasons.
enum ChatStopReason {
  endTurn,
  maxTokens,
  toolUse,
  requiresInteraction,
  refusal,
  error,
  unknown,
}

extension ChatStopReasonX on ChatStopReason {
  /// `true` when the user should be told the reply may be incomplete.
  /// `endTurn` is the only "all good" outcome.
  bool get isAbnormal => switch (this) {
    ChatStopReason.endTurn || ChatStopReason.requiresInteraction => false,
    ChatStopReason.maxTokens ||
    ChatStopReason.toolUse ||
    ChatStopReason.refusal ||
    ChatStopReason.error ||
    ChatStopReason.unknown => true,
  };

  bool get allowsContinuation => switch (this) {
    ChatStopReason.maxTokens ||
    ChatStopReason.toolUse ||
    ChatStopReason.error ||
    ChatStopReason.unknown => true,
    ChatStopReason.endTurn ||
    ChatStopReason.requiresInteraction ||
    ChatStopReason.refusal => false,
  };

  static ChatStopReason parse(String? wire) => switch (wire) {
    'end_turn' => ChatStopReason.endTurn,
    'max_tokens' => ChatStopReason.maxTokens,
    'tool_use' => ChatStopReason.toolUse,
    'requires_interaction' => ChatStopReason.requiresInteraction,
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
    this.status = ToolInvocationStatus.completed,
    this.decisionSelection,
    this.interactionResponse,
    this.applyState,
    this.partialInputJson,
  });

  final String id;
  final String name;
  final Object? input;
  final Object? output;
  final ToolInvocationStatus status;
  final DecisionSelection? decisionSelection;
  final AiInteractionResponse? interactionResponse;
  final String? partialInputJson;

  /// Apply state for `propose_*` tool calls. `null` for read-only
  /// tools and for propose tools the user hasn't acted on yet (the UI
  /// treats null and `pending` identically; null keeps the JSON payload
  /// quiet for non-propose calls so we don't bloat persisted history).
  final ProposalApplyState? applyState;

  ToolInvocation copyWith({
    String? name,
    Object? input,
    Object? output,
    ToolInvocationStatus? status,
    DecisionSelection? decisionSelection,
    AiInteractionResponse? interactionResponse,
    String? partialInputJson,
    ProposalApplyState? applyState,
    bool clearApplyState = false,
  }) => ToolInvocation(
    id: id,
    name: name ?? this.name,
    input: input ?? this.input,
    output: output ?? this.output,
    status: status ?? this.status,
    decisionSelection: decisionSelection ?? this.decisionSelection,
    interactionResponse: interactionResponse ?? this.interactionResponse,
    partialInputJson: partialInputJson ?? this.partialInputJson,
    applyState: clearApplyState ? null : (applyState ?? this.applyState),
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'input': input,
    'status': status.wire,
    if (decisionSelection != null)
      'decision_selection': decisionSelection!.toJson(),
    if (interactionResponse != null)
      'interaction_response': interactionResponse!.toJson(),
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
    final rawSelection = json['decision_selection'];
    final selection = rawSelection is Map
        ? DecisionSelection.fromJson(
            rawSelection.map((k, v) => MapEntry(k.toString(), v)),
          )
        : null;
    final interactionResponse = AiInteractionResponse.tryParse(
      json['interaction_response'],
    );
    return ToolInvocation(
      id: (json['id'] ?? '') as String,
      name: (json['name'] ?? '') as String,
      input: json['input'],
      output: json['output'],
      status: ToolInvocationStatusX.parse(json['status'] as String?),
      decisionSelection: selection,
      interactionResponse: interactionResponse,
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

class DecisionSelection {
  const DecisionSelection({
    required this.optionId,
    required this.label,
    required this.reply,
    required this.selectedAt,
  });

  final String optionId;
  final String label;
  final String reply;
  final DateTime selectedAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'option_id': optionId,
    'label': label,
    'reply': reply,
    'selected_at': selectedAt.toIso8601String(),
  };

  factory DecisionSelection.fromJson(Map<String, Object?> json) {
    return DecisionSelection(
      optionId: (json['option_id'] as String?) ?? '',
      label: (json['label'] as String?) ?? '',
      reply: (json['reply'] as String?) ?? '',
      selectedAt:
          DateTime.tryParse((json['selected_at'] as String?) ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
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
    this.progress,
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
  final LongTaskProgress? progress;
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
    LongTaskProgress? progress,
    bool clearProgress = false,
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
    progress: clearProgress ? null : (progress ?? this.progress),
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
    this.preview,
    this.messageCount = 0,
    this.pinned = false,
    this.archived = false,
  });

  final String id;
  final String ownerUserId;
  final String title;
  final String? model;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastMessageAt;

  /// Last non-empty user/assistant content for the history list.
  /// Loaded with the session row (subquery); not persisted as its own column.
  final String? preview;

  /// Total messages in the session (all roles). Used for list meta only.
  final int messageCount;

  /// User-pinned threads float above recency groups.
  final bool pinned;

  /// Archived threads are hidden from the active list unless the user
  /// opens the archive filter.
  final bool archived;

  ChatSession copyWith({
    String? title,
    String? model,
    DateTime? lastMessageAt,
    String? preview,
    int? messageCount,
    bool? pinned,
    bool? archived,
    DateTime? updatedAt,
  }) {
    return ChatSession(
      id: id,
      ownerUserId: ownerUserId,
      title: title ?? this.title,
      model: model ?? this.model,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      preview: preview ?? this.preview,
      messageCount: messageCount ?? this.messageCount,
      pinned: pinned ?? this.pinned,
      archived: archived ?? this.archived,
    );
  }
}
