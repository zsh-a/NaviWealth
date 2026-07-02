part of 'chat_repository.dart';

mixin _ChatRepositorySessions {
  ChatHistoryStore get _store;
  Uuid get _uuid;

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
}

Future<void> _ensureChatSessionExists(
  ChatHistoryStore store, {
  required String sessionId,
  required String ownerUserId,
  String? model,
}) async {
  final existing = await store.findSession(sessionId);
  if (existing != null) {
    if (existing.ownerUserId != ownerUserId) {
      throw StateError('chat session $sessionId belongs to another user');
    }
    return;
  }
  final now = DateTime.now().toUtc();
  await store.insertSession(
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

Future<void> _autotitleChatSessionIfNeeded(
  ChatHistoryStore store,
  String sessionId,
  String firstUserText,
) async {
  final session = await store.findSession(sessionId);
  if (session == null) return;
  if (session.title != kNewSessionTitle) return;
  final trimmed = firstUserText.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (trimmed.isEmpty) return;
  // Approximate "two dozen visible glyphs" by character count. CJK
  // sequences with combining marks may be slightly under; close
  // enough for a thread title shown in a sidebar.
  final title = trimmed.length <= 24 ? trimmed : '${trimmed.substring(0, 24)}…';
  await store.renameSession(sessionId, title);
}
