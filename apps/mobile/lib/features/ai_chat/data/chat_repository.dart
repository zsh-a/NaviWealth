import 'dart:async';

import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

import '../../../core/ai/contracts/contracts.dart';
import '../../../core/ai/freshness/freshness_gate.dart';
import '../../../core/ai/trace/trace.dart';
import '../../../core/auth/providers.dart';
import '../domain/chat_events.dart';
import '../domain/chat_models.dart';
import '../domain/proposal_apply_state.dart';
import 'ai_chat_api_client.dart';
import 'chat_history_store.dart';
import 'context_window.dart';

/// Output of [ChatTracePrep]: the [ContextPack] sent on the wire,
/// the seed [AiTrace] that the repository finalises after the stream
/// closes, and the local HLC snapshot taken at request start (used
/// by the freshness gate when tool_result frames carry a
/// [Freshness] watermark). Any field may be `null` if the caller
/// chose not to wire AI tracing for this repository instance
/// (legacy tests, etc.).
typedef ChatTracePrepResult = ({
  ContextPack? pack,
  AiTrace? traceSeed,
  String? localHlcText,
});

/// Closure that builds the per-request ContextPack + AiTrace seed.
/// Lives in providers.dart so it can capture Riverpod `Ref` without
/// pulling provider state into the repository's constructor surface.
typedef ChatTracePrep =
    Future<ChatTracePrepResult> Function({required String requestId});

/// Sentinel value for new session titles. UI layer should resolve to
/// localized string when displaying.
const kNewSessionTitle = '新对话';

/// Sentinel error message for cancelled requests. UI layer should
/// resolve to localized string when displaying.
const kCancelledError = '已取消';
const _userCancelledReason = 'user cancelled';

/// Outcome of a `sendMessage` turn — surfaced to the controller so the
/// UI can flip from "streaming" back to "idle" deterministically.
enum SendOutcome { completed, errored, cancelled }

/// Sentinel error message used when [SseIdleTimeout] fires. The UI layer
/// should resolve to a localized string when displaying.
const kIdleTimeoutError = '连接已中断 (无新数据)';

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
    ChatTracePrep? tracePrep,
    AiTraceStore? traceStore,
    void Function(AiTrace finalized)? onTraceFinalized,
    Uuid? uuid,
  }) : _store = store,
       _api = api,
       _sessionReader = sessionReader,
       _portfolioSnapshotReader = portfolioSnapshotReader,
       _tracePrep = tracePrep,
       _traceStore = traceStore,
       _onTraceFinalized = onTraceFinalized,
       _uuid = uuid ?? const Uuid();

  final ChatHistoryStore _store;
  final AiChatApiClient _api;
  final AuthSessionReader _sessionReader;
  final Future<Map<String, Object?>?> Function()? _portfolioSnapshotReader;
  final ChatTracePrep? _tracePrep;
  final AiTraceStore? _traceStore;
  final void Function(AiTrace finalized)? _onTraceFinalized;
  final Uuid _uuid;

  Stream<List<ChatSession>> watchSessions(String ownerUserId) =>
      _store.watchSessions(ownerUserId);

  Stream<List<ChatMessage>> watchMessages(String sessionId) =>
      _store.watchMessages(sessionId);

  /// One-shot read of the user's existing sessions. Used by the AI chat
  /// page bootstrap so it never has to wait on a `StreamProvider.future`
  /// that may not deliver its first emission until the next change
  /// notification fires (an issue we hit with the page getting stuck on
  /// "Preparing conversation…" until the user manually tapped "+").
  Future<List<ChatSession>> listSessions(String ownerUserId) =>
      _store.listSessions(ownerUserId);

  Future<ChatSession?> findSession(String id) => _store.findSession(id);

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
    /// Wave 33 — when this turn was triggered through an
    /// [AiIntentInvocation] (capsule / insight / command), pass the
    /// invocation's `toTraceJson()` here so the finalised trace
    /// records the entry point. Plain "user typed in chat tab" calls
    /// leave this `null`.
    Map<String, Object?>? invocationTrace,
  }) async {
    final session = _sessionReader();
    if (session == null) {
      throw const AiChatRequestException(
        statusCode: 401,
        message: 'not authenticated',
      );
    }
    await _ensureSessionExists(
      sessionId: sessionId,
      ownerUserId: ownerUserId,
      model: model,
    );

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

    // Phase 2-A: build the typed ContextPack + seed an AiTrace keyed by
    // the assistant message id. Failures here are absorbed: chat must
    // never break because the AI transparency layer hiccupped, so the
    // prep closure already returns null on its own errors.
    final prepResult = _tracePrep == null
        ? null
        : await _tracePrep.call(requestId: assistantId);
    final contextPack = prepResult?.pack;
    final traceSeed = prepResult?.traceSeed;
    final localHlcText = prepResult?.localHlcText;
    final traceBuilder = traceSeed == null
        ? null
        : AiTraceBuilder.fromSeed(traceSeed);
    if (traceBuilder != null && invocationTrace != null) {
      traceBuilder.attachInvocation(invocationTrace);
    }
    final toolStarts = <String, DateTime>{};

    // Interleaved record of the assistant turn. `segments` and
    // `invocationOrder` together rebuild the original
    // text → tool → text → tool sequence the model emitted: each new
    // tool boundary closes the current trailing segment and opens a
    // fresh empty one. Invariant: `segments.length ==
    // invocationOrder.length + 1`.
    final segments = <String>[''];
    final invocations = <String, ToolInvocation>{};
    final invocationOrder = <String>[];
    final localCancel = cancelToken ?? CancelToken();
    SendOutcome outcome = SendOutcome.completed;
    // Wave 30: granular terminal reason for the finalised trace.
    // SendOutcome collapses error/cancel into the user-visible shape;
    // the trace surface needs the finer split so the audit page can
    // tell "user cancelled" from "stream errored" from "policy denied".
    TerminalReason terminalReason = TerminalReason.done;
    var sawStreamEvent = false;
    var sawDone = false;

    try {
      // The byte-level idle watchdog now lives inside the API client
      // (see [DioAiChatApiClient.chat]) so it counts the backend's
      // SSE keepalive comments as activity, not just real events. We
      // only need to surface its sentinel error here.
      final stream = _api.chat(
        session: session,
        messages: wireMessages,
        portfolioSnapshot: portfolioSnapshot,
        contextPack: contextPack,
        model: model,
        cancelToken: localCancel,
      );

      await for (final event in stream) {
        sawStreamEvent = true;
        switch (event) {
          case TextEvent(:final text):
            segments[segments.length - 1] = segments.last + text;
            assistant = assistant.copyWith(
              content: segments.join(),
              textSegments: List<String>.unmodifiable(segments),
            );
            await _store.updateMessage(assistant);
          case ToolCallEvent(:final id, :final name, :final input):
            // First sighting of this id → close the active text
            // segment and start a new trailing one.
            if (!invocationOrder.contains(id)) {
              invocationOrder.add(id);
              segments.add('');
            }
            invocations[id] = ToolInvocation(id: id, name: name, input: input);
            toolStarts[id] = DateTime.now().toUtc();
            assistant = assistant.copyWith(
              toolCalls: [for (final k in invocationOrder) invocations[k]!],
              textSegments: List<String>.unmodifiable(segments),
            );
            await _store.updateMessage(assistant);
          case ToolResultEvent(:final id, :final output, :final freshness):
            final existing = invocations[id];
            // A tool_result for an unseen id means the call was
            // synthesised server-side (e.g. proposal cap rejection).
            // Treat it like a fresh tool call so the segment list
            // still satisfies its length invariant.
            if (!invocationOrder.contains(id)) {
              invocationOrder.add(id);
              segments.add('');
            }
            invocations[id] = existing == null
                ? ToolInvocation(id: id, name: '', input: null, output: output)
                : existing.copyWith(output: output);
            assistant = assistant.copyWith(
              toolCalls: [for (final k in invocationOrder) invocations[k]!],
              textSegments: List<String>.unmodifiable(segments),
            );
            await _store.updateMessage(assistant);
            if (traceBuilder != null) {
              final start = toolStarts[id];
              final duration = start == null
                  ? Duration.zero
                  : DateTime.now().toUtc().difference(start);
              traceBuilder.addToolCall(
                name: invocations[id]?.name ?? '',
                duration: duration,
                ok: !_isToolError(output),
              );
              // Freshness gate (docs/ai-architecture.md §4.2 Phase 2):
              // when the read-model watermark is behind our local HLC,
              // record the read_model name. The next prep closure
              // picks these up off the finalised AiTrace and injects
              // `force_refresh_read_models` into the next ContextPack
              // so the cloud re-projects before dispatching.
              if (freshness != null && localHlcText != null) {
                if (isStale(
                  cloud: freshness,
                  localHlcText: localHlcText,
                )) {
                  traceBuilder.markStaleReadModel(freshness.readModel);
                }
              }
            }
          case ErrorEvent(:final message):
            outcome = SendOutcome.errored;
            terminalReason = TerminalReason.streamError;
            assistant = assistant.copyWith(
              status: ChatMessageStatus.errored,
              errorMessage: message,
            );
            await _store.updateMessage(assistant);
          case DoneEvent(:final stopReason):
            sawDone = true;
            // Only flip to complete if no error frame already promoted
            // the message to errored. The stop reason is captured either
            // way so the UI can distinguish "natural end" from
            // "max_tokens / tool_use budget / refusal" without changing
            // the persistence model.
            final reason = ChatStopReasonX.parse(stopReason);
            if (assistant.status != ChatMessageStatus.errored) {
              assistant = assistant.copyWith(
                status: ChatMessageStatus.complete,
                stopReason: reason,
              );
            } else {
              assistant = assistant.copyWith(stopReason: reason);
            }
            await _store.updateMessage(assistant);
        }
      }
      if (!sawStreamEvent) {
        outcome = SendOutcome.errored;
        terminalReason = TerminalReason.closedEarly;
        assistant = assistant.copyWith(
          status: ChatMessageStatus.errored,
          errorMessage: 'AI response stream ended without any events',
          stopReason: ChatStopReason.error,
        );
        await _store.updateMessage(assistant);
      } else if (!sawDone && assistant.status == ChatMessageStatus.streaming) {
        outcome = SendOutcome.errored;
        terminalReason = TerminalReason.closedEarly;
        assistant = assistant.copyWith(
          status: ChatMessageStatus.errored,
          errorMessage: 'AI response stream ended before done',
          stopReason: ChatStopReason.error,
        );
        await _store.updateMessage(assistant);
      }
    } catch (e) {
      if (e is SseIdleTimeout) {
        outcome = SendOutcome.errored;
        terminalReason = TerminalReason.streamError;
        assistant = assistant.copyWith(
          status: ChatMessageStatus.errored,
          errorMessage: kIdleTimeoutError,
          stopReason: ChatStopReason.error,
        );
        await _store.updateMessage(assistant);
      } else if (_isUserCancelled(localCancel)) {
        outcome = SendOutcome.cancelled;
        terminalReason = TerminalReason.userCancel;
        assistant = assistant.copyWith(
          status: ChatMessageStatus.errored,
          errorMessage: kCancelledError,
          stopReason: ChatStopReason.error,
        );
        await _store.updateMessage(assistant);
      } else {
        outcome = SendOutcome.errored;
        terminalReason = TerminalReason.streamError;
        assistant = assistant.copyWith(
          status: ChatMessageStatus.errored,
          errorMessage: _describeError(e),
          stopReason: ChatStopReason.error,
        );
        await _store.updateMessage(assistant);
      }
    } finally {
      await _store.touchSession(sessionId, DateTime.now().toUtc());
      // Append the trace last so a failure here can never sneak past
      // and skip session.touch — chat history takes priority over
      // transparency. The optional onTraceFinalized callback is the
      // bridge that feeds stale-read-model names into the next chat
      // request's FreshnessHint (lib/.../providers.dart).
      if (traceBuilder != null && _traceStore != null) {
        try {
          final trace = traceBuilder.finalize(
            finishedAt: DateTime.now().toUtc(),
            terminalReason: terminalReason,
          );
          await _traceStore.append(trace);
          _onTraceFinalized?.call(trace);
        } catch (_) {
          // Tracing is best-effort.
        }
      }
    }

    return outcome;
  }

  /// `true` when a tool result payload represents a failure (the
  /// backend uses a `{ "error": "...", "code": "..." }` shape for
  /// synthesised errors like the proposal cap or guardrail rejections).
  static bool _isToolError(Object? output) {
    if (output is! Map) return false;
    return output['error'] is String;
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
    await _ensureSessionExists(sessionId: sessionId, ownerUserId: ownerUserId);
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

  Future<void> _ensureSessionExists({
    required String sessionId,
    required String ownerUserId,
    String? model,
  }) async {
    final existing = await _store.findSession(sessionId);
    if (existing != null) {
      if (existing.ownerUserId != ownerUserId) {
        throw StateError('chat session $sessionId belongs to another user');
      }
      return;
    }
    final now = DateTime.now().toUtc();
    await _store.insertSession(
      ChatSession(
        id: sessionId,
        ownerUserId: ownerUserId,
        title: kNewSessionTitle,
        createdAt: now,
        updatedAt: now,
        lastMessageAt: null,
        model: model,
      ),
    );
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

  bool _isUserCancelled(CancelToken token) {
    return token.cancelError?.error == _userCancelledReason;
  }
}
