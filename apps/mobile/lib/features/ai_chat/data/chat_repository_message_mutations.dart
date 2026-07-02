part of 'chat_repository.dart';

mixin _ChatRepositoryMessageMutations {
  ChatHistoryStore get _store;
  Uuid get _uuid;

  /// Mutate the apply state of one tool invocation inside [messageId].
  ///
  /// Used by propose-card flow: confirm / cancel / undo each call this
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

  Future<void> recordDecisionSelection({
    required String sessionId,
    required String messageId,
    required String toolInvocationId,
    required DecisionSelection selection,
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
          t.copyWith(decisionSelection: selection)
        else
          t,
    ];
    await _store.updateMessage(message.copyWith(toolCalls: updatedToolCalls));
  }

  /// Discard the target user message AND every message that follows it
  /// (assistant reply, follow-up turns, system notices). Branch
  /// semantics: editing a past prompt overwrites the conversation from
  /// that point on, since the new wording will yield a different
  /// timeline and we don't keep history-branches today.
  ///
  /// Returns `false` when the message id is unknown or doesn't point
  /// at a user turn (defensive; the UI gates this affordance to
  /// trailing user messages, but a stale id from a fast tap is
  /// possible).
  Future<bool> discardFromUserMessage({
    required String sessionId,
    required String messageId,
  }) async {
    final messages = await _store.listMessages(sessionId);
    final idx = messages.indexWhere((m) => m.id == messageId);
    if (idx < 0) return false;
    if (messages[idx].role != ChatRole.user) return false;
    for (var i = idx; i < messages.length; i++) {
      await _store.deleteMessage(messages[i].id);
    }
    return true;
  }

  /// Discard the last assistant turn and the user turn that produced
  /// it, returning the user-turn content so the caller can re-send it
  /// through [sendMessage]. The two messages are removed in one go so
  /// the timeline never briefly shows a dangling user turn.
  ///
  /// Returns `null` when no regeneration is possible — e.g. the last
  /// message isn't an assistant turn, or there's no preceding user
  /// turn to re-send. Streaming assistant turns are rejected so a
  /// regenerate tap during a live stream is a no-op rather than
  /// silently cancelling the in-flight call.
  Future<String?> prepareRegenerateLastAssistant(String sessionId) async {
    final messages = await _store.listMessages(sessionId);
    if (messages.isEmpty) return null;
    // Walk from the end to find the last *assistant* row (skipping
    // trailing system notices). Once found, the immediately preceding
    // user row is what we'll re-send. Anything in between is a system
    // notice, which we leave in place — those are timeline annotations,
    // not turns.
    int assistantIdx = -1;
    for (var i = messages.length - 1; i >= 0; i--) {
      if (messages[i].role == ChatRole.assistant) {
        assistantIdx = i;
        break;
      }
    }
    if (assistantIdx < 0) return null;
    final assistant = messages[assistantIdx];
    if (assistant.status == ChatMessageStatus.streaming) return null;
    int userIdx = -1;
    for (var i = assistantIdx - 1; i >= 0; i--) {
      if (messages[i].role == ChatRole.user) {
        userIdx = i;
        break;
      }
    }
    if (userIdx < 0) return null;
    final user = messages[userIdx];
    await _store.deleteMessage(assistant.id);
    await _store.deleteMessage(user.id);
    return user.content;
  }

  /// Insert an in-band system message into the timeline. Used both
  /// internally (context-window truncation notices) and by the chat
  /// controller (staleness warning when the pre-chat sync gate
  /// times out).
  Future<void> insertSystemNotice({
    required String sessionId,
    required String ownerUserId,
    required String content,
  }) async {
    await _ensureChatSessionExists(
      _store,
      sessionId: sessionId,
      ownerUserId: ownerUserId,
    );
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
}
