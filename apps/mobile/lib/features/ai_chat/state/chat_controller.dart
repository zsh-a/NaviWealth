import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/providers.dart';
import '../data/providers.dart';

/// UI-side state for one chat session: are we currently streaming, and
/// the cancel handle for the in-flight turn.
///
/// Persisted state (sessions list, message timeline) lives in Drift and
/// flows through `chatSessionsStreamProvider` /
/// `chatMessagesStreamProvider`. This controller only models ephemeral
/// UI signals.
class ChatTurnState {
  const ChatTurnState({this.isStreaming = false, this.cancelToken});

  final bool isStreaming;
  final CancelToken? cancelToken;

  ChatTurnState copyWith({bool? isStreaming, CancelToken? cancelToken}) =>
      ChatTurnState(
        isStreaming: isStreaming ?? this.isStreaming,
        cancelToken: cancelToken ?? this.cancelToken,
      );
}

class ChatController extends StateNotifier<ChatTurnState> {
  ChatController({required this.ref, required this.sessionId})
    : super(const ChatTurnState());

  final Ref ref;
  final String sessionId;

  /// Send [content] as the next user turn. Concurrent calls are
  /// rejected — the UI disables the send button while streaming.
  Future<void> send(String content) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty || state.isStreaming) return;

    final session = ref.read(authSessionReaderProvider)();
    if (session == null) {
      // Without a session, the repository would throw; surface that
      // up front by leaving state idle and letting the page render
      // a "log in to chat" notice.
      return;
    }

    final cancelToken = CancelToken();
    state = state.copyWith(isStreaming: true, cancelToken: cancelToken);

    try {
      final repo = await ref.read(chatRepositoryProvider.future);
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
