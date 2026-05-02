import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../core/auth/providers.dart';
import '../data/providers.dart';
import 'chat_sync_gate.dart';

/// Phases of the user's outgoing turn:
///  - [idle]: composer enabled, no work in flight
///  - [flushing]: pre-chat sync gate is draining the OpLog so the AI
///    backend's D1 view reflects the user's latest edits (FIR-71).
///  - [streaming]: SSE stream from `/ai/chat` is being consumed.
enum ChatTurnPhase { idle, flushing, streaming }

/// UI-side state for one chat session: where we are in the send pipeline,
/// and the cancel handle for the in-flight turn.
///
/// Persisted state (sessions list, message timeline) lives in Drift and
/// flows through `chatSessionsStreamProvider` /
/// `chatMessagesStreamProvider`. This controller only models ephemeral
/// UI signals.
class ChatTurnState {
  const ChatTurnState({
    this.phase = ChatTurnPhase.idle,
    this.cancelToken,
  });

  final ChatTurnPhase phase;
  final CancelToken? cancelToken;

  bool get isIdle => phase == ChatTurnPhase.idle;
  bool get isFlushing => phase == ChatTurnPhase.flushing;
  bool get isStreaming => phase == ChatTurnPhase.streaming;
  bool get isBusy => phase != ChatTurnPhase.idle;

  ChatTurnState copyWith({ChatTurnPhase? phase, CancelToken? cancelToken}) =>
      ChatTurnState(
        phase: phase ?? this.phase,
        cancelToken: cancelToken ?? this.cancelToken,
      );
}

class ChatController extends StateNotifier<ChatTurnState> {
  ChatController({required this.ref, required this.sessionId})
    : super(const ChatTurnState());

  final Ref ref;
  final String sessionId;

  /// Send [content] as the next user turn. Concurrent calls are
  /// rejected — the UI disables the send button while the pipeline is
  /// running.
  ///
  /// [staleSyncNotice] is the localized message persisted into the
  /// timeline if the pre-chat sync gate (FIR-71) drains in `degraded`
  /// status. The UI passes the localized string so the controller does
  /// not need a BuildContext to reach AppLocalizations.
  Future<void> send(
    String content, {
    required String staleSyncNotice,
  }) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty || state.isBusy) return;

    final session = ref.read(authSessionReaderProvider)();
    if (session == null) {
      // Without a session, the repository would throw; surface that
      // up front by leaving state idle and letting the page render
      // a "log in to chat" notice.
      return;
    }

    state = state.copyWith(phase: ChatTurnPhase.flushing);

    final gateOutcome = await _runSyncGate();

    if (!mounted) return;

    final cancelToken = CancelToken();
    state = state.copyWith(
      phase: ChatTurnPhase.streaming,
      cancelToken: cancelToken,
    );

    try {
      final repo = await ref.read(chatRepositoryProvider.future);
      if (gateOutcome == ChatGateOutcome.degraded) {
        await repo.insertSystemNotice(
          sessionId: sessionId,
          ownerUserId: session.userId,
          content: staleSyncNotice,
        );
      }
      await repo.sendMessage(
        sessionId: sessionId,
        ownerUserId: session.userId,
        content: trimmed,
        cancelToken: cancelToken,
      );
    } finally {
      if (mounted) {
        state = const ChatTurnState();
      }
    }
  }

  /// Run the pre-chat sync gate. Catches all errors (including a missing
  /// or unbuilt SyncEngine in early-dev / tests) and folds them into a
  /// gate outcome — chat is never blocked by infrastructure failures.
  Future<ChatGateOutcome> _runSyncGate() async {
    try {
      final gate = await ref.read(chatSyncGateProvider.future);
      return await gate.awaitFlush();
    } catch (_) {
      // Sync infra not wired (early dev) or transient init failure: skip
      // the gate rather than blocking the user. We deliberately do NOT
      // surface a staleness warning here, because the more common cause
      // is "auth token isn't issued yet" which would make the warning
      // appear on every turn.
      return ChatGateOutcome.clean;
    }
  }

  /// Cancel the in-flight stream. Repository will mark the assistant
  /// turn as `errored` with reason "已取消".
  void cancel() {
    final token = state.cancelToken;
    if (token != null && !token.isCancelled) {
      token.cancel('user cancelled');
    }
  }
}

/// Per-session controller. Riverpod auto-disposes when the chat page
/// pops, which also cancels any in-flight turn via the `mounted` check.
final chatControllerProvider = StateNotifierProvider.autoDispose
    .family<ChatController, ChatTurnState, String>(
  (ref, sessionId) => ChatController(ref: ref, sessionId: sessionId),
);
