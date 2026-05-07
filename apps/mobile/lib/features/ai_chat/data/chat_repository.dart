import 'dart:async';

import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

import '../../../core/auth/providers.dart';
import '../domain/chat_events.dart';
import '../domain/chat_models.dart';
import '../domain/proposal_apply_state.dart';
import 'ai_chat_api_client.dart';
import 'chat_history_store.dart';
import 'context_window.dart';

/// Sentinel value for new session titles. UI layer should resolve to
/// localized string when displaying.
const kNewSessionTitle = '新对话';

/// Sentinel error message for cancelled requests. UI layer should
/// resolve to localized string when displaying.
const kCancelledError = '已取消';

/// Outcome of a `sendMessage` turn — surfaced to the controller so the
/// UI can flip from "streaming" back to "idle" deterministically.
enum SendOutcome { completed, errored, cancelled }

/// Combines the chat HTTP client with persistence. Owns the message
/// timeline for one session: writes the user turn synchronously, then
/// drives the SSE stream into the assistant turn row, updating it
/// in-place as `text` / `tool_call` / `tool_result` frames arrive.
class ChatRepository {
  ChatRepository({
    required ChatHistoryStore store,
    required AiChatApiClient api,
    required AuthSessionReader sessionReader,
    Future<Map<String, Object?>?> Function()? portfolioSnapshotReader,
    Uuid? uuid,
  }) : _store = store,
       _api = api,
       _sessionReader = sessionReader,
       _portfolioSnapshotReader = portfolioSnapshotReader,
       _uuid = uuid ?? const Uuid();

  final ChatHistoryStore _store;
  final AiChatApiClient _api;
  final AuthSessionReader _sessionReader;
  final Future<Map<String, Object?>?> Function()? _portfolioSnapshotReader;
  final Uuid _uuid;

  Stream<List<ChatSession>> watchSessions(String ownerUserId) =>
      _store.watchSessions(ownerUserId);

  Stream<List<ChatMessage>> watchMessages(String sessionId) =>
      _store.watchMessages(sessionId);

  /// Create a new empty thread. Used by the "+" button.
  Future<ChatSession> createSession({
    required String ownerUserId,
    String? title,
    String? model,
  }) async {
    final now = DateTime.now().toUtc();
    final session = ChatSession(
      id: _uuid.v4(),
      ownerUserId: ownerUserId,
      title: title ?? kNewSessionTitle,
      createdAt: now,
      updatedAt: now,
      lastMessageAt: null,
      model: model,
    );
    await _store.insertSession(session);
    return session;
  }

  Future<void> renameSession(String id, String title) =>
      _store.renameSession(id, title);

  Future<void> deleteSession(String id) => _store.deleteSession(id);

  /// Send [content] as the next user turn in [sessionId] and stream the
  /// assistant's response. Returns when the stream terminates (either
  /// `done`, an error, or [cancelToken] firing).
  ///
  /// Side effects:
  ///   1. Persist the user turn.
  ///   2. Persist a placeholder assistant turn in `streaming` state.
  ///   3. As each SSE frame arrives, mutate the placeholder and call
  ///      `updateMessage` so subscribers see the text grow.
  ///   4. On `done`, mark the assistant turn `complete`. On `error` /
  ///      stream failure, mark it `errored` and store the message.
  ///   5. Bump the session's `last_message_at`.
  ///   6. If the session title is still the default, autotitle it from
  ///      the first user turn (first ~24 chars of the prompt).
  Future<SendOutcome> sendMessage({
    required String sessionId,
    required String ownerUserId,
    required String content,
    String? systemContext,
    String? model,
    CancelToken? cancelToken,
  }) async {
    final session = _sessionReader();
    if (session == null) {
      throw const AiChatRequestException(
        statusCode: 401,
        message: 'not authenticated',
      );
    }

    final history = await _store.listMessages(sessionId);

    final now = DateTime.now().toUtc();
    final userMessage = ChatMessage(
      id: _uuid.v4(),
      sessionId: sessionId,
      ownerUserId: ownerUserId,
      role: ChatRole.user,
      content: content,
      status: ChatMessageStatus.complete,
      createdAt: now,
    );
    await _store.insertMessage(userMessage);
    await _autotitleIfNeeded(sessionId, content);

    final assistantId = _uuid.v4();
    var assistant = ChatMessage(
      id: assistantId,
      sessionId: sessionId,
      ownerUserId: ownerUserId,
      role: ChatRole.assistant,
      content: '',
      status: ChatMessageStatus.streaming,
      // Force the assistant placeholder strictly after the user turn so
      // the `ORDER BY created_at, id` sort never flips them when both
      // inserts land on the same wall millisecond — UUIDs sort
      // arbitrarily and on a fast machine the assistant id can land
      // ahead of the user id.
      createdAt: now.add(const Duration(milliseconds: 1)),
    );
    await _store.insertMessage(assistant);

    final ctx = buildContextWindow(history: history, pending: content);

    // Prepend route context without using a system role; the backend owns the
    // system prompt and accepts only user / assistant turns on this endpoint.
    final wireMessages = <WireMessage>[
      if (systemContext != null && systemContext.isNotEmpty)
        WireMessage(role: 'user', content: 'Context:\n$systemContext'),
      ...ctx.wire,
    ];
    if (ctx.droppedTurns > 0) {
      await insertSystemNotice(
        sessionId: sessionId,
        ownerUserId: ownerUserId,
        content: ChatRepository.contextTruncatedNotice(ctx.droppedTurns),
      );
    }
    final portfolioSnapshot = await _portfolioSnapshotReader?.call();

    final buffer = StringBuffer();
    final invocations = <String, ToolInvocation>{};
    final invocationOrder = <String>[];
    final localCancel = cancelToken ?? CancelToken();
    SendOutcome outcome = SendOutcome.completed;

    try {
      final stream = _api.chat(
        session: session,
        messages: wireMessages,
        portfolioSnapshot: portfolioSnapshot,
        model: model,
        cancelToken: localCancel,
      );

      await for (final event in stream) {
        switch (event) {
          case TextEvent(:final text):
            buffer.write(text);
            assistant = assistant.copyWith(content: buffer.toString());
            await _store.updateMessage(assistant);
          case ToolCallEvent(:final id, :final name, :final input):
            invocations[id] = ToolInvocation(id: id, name: name, input: input);
            if (!invocationOrder.contains(id)) invocationOrder.add(id);
            assistant = assistant.copyWith(
              toolCalls: [for (final k in invocationOrder) invocations[k]!],
            );
            await _store.updateMessage(assistant);
          case ToolResultEvent(:final id, :final output):
            final existing = invocations[id];
            invocations[id] = existing == null
                ? ToolInvocation(id: id, name: '', input: null, output: output)
                : existing.copyWith(output: output);
            if (!invocationOrder.contains(id)) invocationOrder.add(id);
            assistant = assistant.copyWith(
              toolCalls: [for (final k in invocationOrder) invocations[k]!],
            );
            await _store.updateMessage(assistant);
          case ErrorEvent(:final message):
            outcome = SendOutcome.errored;
            assistant = assistant.copyWith(
              status: ChatMessageStatus.errored,
              errorMessage: message,
            );
            await _store.updateMessage(assistant);
          case DoneEvent():
            // Only flip to complete if no error frame already promoted
            // the message to errored.
            if (assistant.status != ChatMessageStatus.errored) {
              assistant = assistant.copyWith(
                status: ChatMessageStatus.complete,
              );
              await _store.updateMessage(assistant);
            }
        }
      }
    } catch (e) {
      if (localCancel.isCancelled) {
        outcome = SendOutcome.cancelled;
        assistant = assistant.copyWith(
          status: ChatMessageStatus.errored,
          errorMessage: kCancelledError,
        );
        await _store.updateMessage(assistant);
      } else {
        outcome = SendOutcome.errored;
        assistant = assistant.copyWith(
          status: ChatMessageStatus.errored,
          errorMessage: _describeError(e),
        );
        await _store.updateMessage(assistant);
      }
    } finally {
      await _store.touchSession(sessionId, DateTime.now().toUtc());
    }

    return outcome;
  }

  /// Mutate the apply state of one tool invocation inside [messageId].
  ///
  /// Used by FIR-67 propose-card flow: confirm / cancel / undo each call this
  /// to persist the new status alongside the existing assistant message so a
  /// reload preserves the user's decision.
  Future<void> updateToolApplyState({
    required String sessionId,
    required String messageId,
    required String toolInvocationId,
    required ProposalApplyState? newState,
  }) async {
    final messages = await _store.listMessages(sessionId);
    final message = messages.firstWhere(
      (m) => m.id == messageId,
      orElse: () => throw StateError(
        'message $messageId not found in session $sessionId',
      ),
    );
    final updatedToolCalls = <ToolInvocation>[
      for (final t in message.toolCalls)
        if (t.id == toolInvocationId)
          t.copyWith(applyState: newState, clearApplyState: newState == null)
        else
          t,
    ];
    await _store.updateMessage(message.copyWith(toolCalls: updatedToolCalls));
  }

  /// Insert an in-band system message into the timeline. Used both
  /// internally (context-window truncation notices) and by the chat
  /// controller (FIR-71 staleness warning when the pre-chat sync gate
  /// times out).
  Future<void> insertSystemNotice({
    required String sessionId,
    required String ownerUserId,
    required String content,
  }) async {
    final notice = ChatMessage(
      id: _uuid.v4(),
      sessionId: sessionId,
      ownerUserId: ownerUserId,
      role: ChatRole.system,
      content: content,
      status: ChatMessageStatus.complete,
      createdAt: DateTime.now().toUtc(),
    );
    await _store.insertMessage(notice);
  }

  Future<void> _autotitleIfNeeded(
    String sessionId,
    String firstUserText,
  ) async {
    final session = await _store.findSession(sessionId);
    if (session == null) return;
    if (session.title != kNewSessionTitle) return;
    final trimmed = firstUserText.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (trimmed.isEmpty) return;
    // Approximate "two dozen visible glyphs" by character count. CJK
    // sequences with combining marks may be slightly under; close
    // enough for a thread title shown in a sidebar.
    final title = trimmed.length <= 24
        ? trimmed
        : '${trimmed.substring(0, 24)}…';
    await _store.renameSession(sessionId, title);
  }

  /// Generates the context-truncation notice text. Callers in the UI layer
  /// may prefer `AppLocalizations.chatContextTruncated(count)` for proper
  /// i18n; this static is provided for data-layer callers that lack
  /// BuildContext.
  static String contextTruncatedNotice(int count) =>
      '已折叠 $count 条更早的历史以控制上下文长度。';

  String _describeError(Object e) {
    if (e is AiChatRequestException) {
      return e.message;
    }
    return e.toString();
  }
}
