import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../core/auth/current_user.dart';
import '../data/providers.dart';
import '../domain/chat_models.dart';
import '../domain/chat_turn_metadata.dart';

/// Phases of the user's outgoing turn:
///  - [idle]: composer enabled, no work in flight
///  - [streaming]: runtime events are being consumed.
enum ChatTurnPhase { idle, streaming }

/// UI-side state for one chat session: where we are in the send pipeline,
/// and the cancel handle for the in-flight turn.
///
/// Persisted state (sessions list, message timeline) lives in Drift and
/// flows through `chatSessionsStreamProvider` /
/// `chatMessagesStreamProvider`. This controller only models ephemeral
/// UI signals.
class ChatTurnState {
  const ChatTurnState({this.phase = ChatTurnPhase.idle, this.cancelToken});

  final ChatTurnPhase phase;
  final CancelToken? cancelToken;

  bool get isIdle => phase == ChatTurnPhase.idle;
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
  Future<void> send(
    String content, {
    String? systemContext,
    ChatTurnMetadata turnMetadata = const ChatTurnMetadata.empty(),
  }) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty || state.isBusy) return;

    // Device-only AI works in local-only mode too, so scope by the active
    // user id (synthetic [kLocalOnlyUserId] when account-less) rather than a
    // cloud session. `null` only before auth settles — the page guards that.
    final ownerUserId = ref.read(activeUserIdProvider);
    if (ownerUserId == null) return;

    final cancelToken = CancelToken();
    state = state.copyWith(
      phase: ChatTurnPhase.streaming,
      cancelToken: cancelToken,
    );

    try {
      final repo = await ref.read(chatRepositoryProvider.future);
      await repo.sendMessage(
        sessionId: sessionId,
        ownerUserId: ownerUserId,
        content: trimmed,
        systemContext: systemContext,
        turnMetadata: turnMetadata,
        cancelToken: cancelToken,
      );
    } finally {
      if (mounted) {
        state = const ChatTurnState();
      }
    }
  }

  Future<void> chooseDecision({
    required String messageId,
    required String toolInvocationId,
    required DecisionSelection selection,
    String? systemContext,
    Map<String, Object?>? invocationTrace,
  }) async {
    if (state.isBusy) return;
    final repo = await ref.read(chatRepositoryProvider.future);
    final interactionResponse = await repo.recordDecisionSelection(
      sessionId: sessionId,
      messageId: messageId,
      toolInvocationId: toolInvocationId,
      selection: selection,
    );
    await send(
      selection.reply,
      systemContext: systemContext,
      turnMetadata: ChatTurnMetadata.forDecision(
        selection: selection,
        messageId: messageId,
        toolInvocationId: toolInvocationId,
        interactionResponse: interactionResponse,
        invocationTrace: invocationTrace,
      ),
    );
  }

  /// Branch-replace a past user turn: discards the message + every
  /// reply (and follow-up turn) after it, then sends [newContent] as
  /// a fresh user turn. No-op when a turn is in flight, the new
  /// content is empty, or the message id can't be found / isn't a
  /// user turn.
  Future<void> editAndResend({
    required String messageId,
    required String newContent,
    String? systemContext,
  }) async {
    if (state.isBusy) return;
    final trimmed = newContent.trim();
    if (trimmed.isEmpty) return;
    final repo = await ref.read(chatRepositoryProvider.future);
    final ok = await repo.discardFromUserMessage(
      sessionId: sessionId,
      messageId: messageId,
    );
    if (!ok) return;
    await send(trimmed, systemContext: systemContext);
  }

  /// Re-run the last assistant turn. Discards both the assistant
  /// message and the user message that produced it, then re-sends the
  /// user content through [send]. No-op while a turn is in flight, or
  /// when there's nothing eligible to regenerate (no assistant message,
  /// no preceding user message, or the assistant is still streaming).
  Future<void> regenerateLast({String? systemContext}) async {
    if (state.isBusy) return;
    final repo = await ref.read(chatRepositoryProvider.future);
    final priorContent = await repo.prepareRegenerateLastAssistant(sessionId);
    if (priorContent == null) return;
    await send(priorContent, systemContext: systemContext);
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
