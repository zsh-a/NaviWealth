import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/ai/progress/long_task_progress.dart';
import '../../../core/persistence/app_database.dart';
import '../domain/chat_events.dart';
import '../domain/chat_models.dart';

/// Persistence layer for chat sessions and messages.
///
/// Tables are created via raw DDL in `app_database.dart` (see
/// `_createChatTables`); this class wraps `customSelect` /
/// `customStatement` so the chat feature can ship without regenerating
/// the main Drift `.g.dart`. Round-trip is straightforward TEXT/INTEGER —
/// the only non-obvious bit is that `tool_calls_json` is a serialized
/// array (see `ToolInvocation.encodeList`).
///
/// The watch APIs are reactive via a private broadcast notifier rather
/// than Drift's `readsFrom` mechanism — `readsFrom` requires
/// `TableInfo` objects, and the chat tables are deliberately raw to
/// keep them out of the codegen path. Every mutation bumps the
/// notifier so subscribed streams re-issue their query.
class ChatHistoryStore {
  ChatHistoryStore(this._db);

  final AppDatabase _db;
  final StreamController<void> _changes = StreamController<void>.broadcast();

  void dispose() {
    _changes.close();
  }

  void _notify() {
    if (!_changes.isClosed) _changes.add(null);
  }

  // ─── sessions ──────────────────────────────────────────────────────

  /// Returns sessions for [ownerUserId] ordered by recency
  /// (`last_message_at DESC`, with `created_at DESC` as a tiebreaker for
  /// brand-new threads that have not received any messages yet).
  Stream<List<ChatSession>> watchSessions(String ownerUserId) {
    return _drive(() => _listSessions(ownerUserId));
  }

  /// One-shot read used by the chat page bootstrap. Equivalent to
  /// `watchSessions(ownerUserId).first` but bypasses the StreamController
  /// in [_drive] entirely.
  Future<List<ChatSession>> listSessions(String ownerUserId) =>
      _listSessions(ownerUserId);

  Future<List<ChatSession>> _listSessions(String ownerUserId) async {
    final rows = await _db
        .customSelect(
          // Preview + message_count come from correlated subqueries so the
          // history list stays informative without a denormalized column.
          'SELECT s.*, '
          '('
          '  SELECT m.content FROM chat_messages m '
          '  WHERE m.session_id = s.id '
          '    AND m.role IN (\'user\', \'assistant\', \'error\') '
          '    AND length(trim(m.content)) > 0 '
          '  ORDER BY m.created_at DESC, m.id DESC '
          '  LIMIT 1'
          ') AS preview, '
          '('
          '  SELECT COUNT(*) FROM chat_messages m2 '
          '  WHERE m2.session_id = s.id'
          ') AS message_count '
          'FROM chat_sessions s '
          'WHERE s.owner_user_id = ?1 '
          'ORDER BY COALESCE(s.pinned, 0) DESC, '
          'COALESCE(s.last_message_at, s.created_at) DESC',
          variables: [Variable<String>(ownerUserId)],
        )
        .get();
    return rows.map(_sessionFromRow).toList(growable: false);
  }

  /// Build a per-listener stream that yields once on subscribe and then
  /// each time the store's broadcast notifier fires. Using an explicit
  /// [StreamController] (rather than `async*` over the broadcast) lets
  /// us cancel the broadcast subscription deterministically when the
  /// caller cancels — `async*` over a broadcast can leave the generator
  /// suspended past test teardown.
  Stream<T> _drive<T>(Future<T> Function() snapshot) {
    late StreamController<T> controller;
    StreamSubscription<void>? sub;
    Future<void> push() async {
      try {
        final v = await snapshot();
        if (!controller.isClosed) controller.add(v);
      } catch (e, st) {
        if (!controller.isClosed) controller.addError(e, st);
      }
    }

    controller = StreamController<T>(
      onListen: () {
        sub = _changes.stream.listen((_) => push());
        push();
      },
      onCancel: () async {
        await sub?.cancel();
        sub = null;
      },
    );
    return controller.stream;
  }

  Future<ChatSession?> findSession(String id) async {
    final row = await _db
        .customSelect(
          'SELECT s.*, '
          '('
          '  SELECT m.content FROM chat_messages m '
          '  WHERE m.session_id = s.id '
          '    AND m.role IN (\'user\', \'assistant\', \'error\') '
          '    AND length(trim(m.content)) > 0 '
          '  ORDER BY m.created_at DESC, m.id DESC '
          '  LIMIT 1'
          ') AS preview, '
          '('
          '  SELECT COUNT(*) FROM chat_messages m2 '
          '  WHERE m2.session_id = s.id'
          ') AS message_count '
          'FROM chat_sessions s '
          'WHERE s.id = ?1',
          variables: [Variable<String>(id)],
        )
        .getSingleOrNull();
    return row == null ? null : _sessionFromRow(row);
  }

  Future<void> insertSession(ChatSession session) async {
    await _db.customStatement(
      'INSERT INTO chat_sessions '
      '(id, owner_user_id, title, model, created_at, updated_at, last_message_at, '
      ' pinned, archived) '
      'VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)',
      <Object?>[
        session.id,
        session.ownerUserId,
        session.title,
        session.model,
        session.createdAt.millisecondsSinceEpoch,
        session.updatedAt.millisecondsSinceEpoch,
        session.lastMessageAt?.millisecondsSinceEpoch,
        session.pinned ? 1 : 0,
        session.archived ? 1 : 0,
      ],
    );
    _notify();
  }

  Future<void> renameSession(String id, String title) async {
    await _db.customStatement(
      'UPDATE chat_sessions SET title = ?2, updated_at = ?3 WHERE id = ?1',
      <Object?>[id, title, DateTime.now().millisecondsSinceEpoch],
    );
    _notify();
  }

  Future<void> setSessionPinned(String id, {required bool pinned}) async {
    await _db.customStatement(
      'UPDATE chat_sessions SET pinned = ?2, updated_at = ?3 WHERE id = ?1',
      <Object?>[id, pinned ? 1 : 0, DateTime.now().millisecondsSinceEpoch],
    );
    _notify();
  }

  Future<void> setSessionArchived(String id, {required bool archived}) async {
    await _db.customStatement(
      // Archiving clears pin so the archive list stays simple.
      'UPDATE chat_sessions SET archived = ?2, pinned = CASE WHEN ?2 = 1 THEN 0 ELSE pinned END, '
      'updated_at = ?3 WHERE id = ?1',
      <Object?>[id, archived ? 1 : 0, DateTime.now().millisecondsSinceEpoch],
    );
    _notify();
  }

  Future<void> touchSession(String id, DateTime lastMessageAt) async {
    await _db.customStatement(
      'UPDATE chat_sessions SET last_message_at = ?2, updated_at = ?2 '
      'WHERE id = ?1',
      <Object?>[id, lastMessageAt.millisecondsSinceEpoch],
    );
    _notify();
  }

  Future<void> deleteSession(String id) async {
    // Manually delete messages first — chat tables are created with
    // `FOREIGN KEY ... ON DELETE CASCADE`, but `PRAGMA foreign_keys` is
    // only enabled on the *production* path (see beforeOpen). In tests
    // and on web (where SQLCipher isn't loaded) the cascade may not
    // fire, so do it explicitly here.
    await _db.customStatement(
      'DELETE FROM chat_messages WHERE session_id = ?1',
      <Object?>[id],
    );
    await _db.customStatement(
      'DELETE FROM chat_sessions WHERE id = ?1',
      <Object?>[id],
    );
    _notify();
  }

  /// Permanently delete every archived session owned by [ownerUserId].
  Future<int> deleteArchivedSessions(String ownerUserId) async {
    final rows = await _db
        .customSelect(
          'SELECT id FROM chat_sessions '
          'WHERE owner_user_id = ?1 AND COALESCE(archived, 0) = 1',
          variables: [Variable<String>(ownerUserId)],
        )
        .get();
    if (rows.isEmpty) return 0;
    for (final row in rows) {
      final id = row.read<String>('id');
      await _db.customStatement(
        'DELETE FROM chat_messages WHERE session_id = ?1',
        <Object?>[id],
      );
      await _db.customStatement(
        'DELETE FROM chat_sessions WHERE id = ?1',
        <Object?>[id],
      );
    }
    _notify();
    return rows.length;
  }

  // ─── messages ──────────────────────────────────────────────────────

  Stream<List<ChatMessage>> watchMessages(String sessionId) {
    return _drive(() => listMessages(sessionId));
  }

  Future<List<ChatMessage>> listMessages(String sessionId) async {
    final rows = await _db
        .customSelect(
          'SELECT * FROM chat_messages WHERE session_id = ?1 '
          'ORDER BY created_at ASC, id ASC',
          variables: [Variable<String>(sessionId)],
        )
        .get();
    return rows.map(_messageFromRow).toList(growable: false);
  }

  Future<void> insertMessage(ChatMessage msg) async {
    await _db.customStatement(
      'INSERT INTO chat_messages '
      '(id, session_id, owner_user_id, role, content, tool_calls_json, '
      ' text_segments_json, reasoning_text, usage_json, progress_json, '
      ' status, error_message, stop_reason, created_at) '
      'VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14)',
      <Object?>[
        msg.id,
        msg.sessionId,
        msg.ownerUserId,
        msg.role.wire,
        msg.content,
        msg.toolCalls.isEmpty ? null : ToolInvocation.encodeList(msg.toolCalls),
        _encodeTextSegments(msg.textSegments),
        msg.reasoningText,
        _encodeUsage(msg.usage),
        _encodeProgress(msg.progress),
        msg.status.wire,
        msg.errorMessage,
        _encodeStopReason(msg.stopReason),
        msg.createdAt.millisecondsSinceEpoch,
      ],
    );
    _notify();
  }

  Future<void> updateMessage(ChatMessage msg) async {
    await _db.customStatement(
      'UPDATE chat_messages SET '
      ' content = ?2, tool_calls_json = ?3, text_segments_json = ?4,'
      ' reasoning_text = ?5, usage_json = ?6, progress_json = ?7,'
      ' status = ?8, error_message = ?9, stop_reason = ?10 '
      'WHERE id = ?1',
      <Object?>[
        msg.id,
        msg.content,
        msg.toolCalls.isEmpty ? null : ToolInvocation.encodeList(msg.toolCalls),
        _encodeTextSegments(msg.textSegments),
        msg.reasoningText,
        _encodeUsage(msg.usage),
        _encodeProgress(msg.progress),
        msg.status.wire,
        msg.errorMessage,
        _encodeStopReason(msg.stopReason),
      ],
    );
    _notify();
  }

  /// Drop a single message. Used by the "regenerate" affordance, which
  /// discards the failed/unwanted assistant turn (and its paired user
  /// turn) before re-running the same prompt.
  Future<void> deleteMessage(String id) async {
    await _db.customStatement(
      'DELETE FROM chat_messages WHERE id = ?1',
      <Object?>[id],
    );
    _notify();
  }

  static String? _encodeStopReason(ChatStopReason? reason) => switch (reason) {
    null => null,
    ChatStopReason.endTurn => 'end_turn',
    ChatStopReason.maxTokens => 'max_tokens',
    ChatStopReason.toolUse => 'tool_use',
    ChatStopReason.refusal => 'refusal',
    ChatStopReason.error => 'error',
    ChatStopReason.unknown => 'unknown',
  };

  static String? _encodeTextSegments(List<String> segments) =>
      segments.isEmpty ? null : jsonEncode(segments);

  static List<String> _decodeTextSegments(String? raw) {
    if (raw == null || raw.isEmpty) return const <String>[];
    try {
      final parsed = jsonDecode(raw);
      if (parsed is! List) return const <String>[];
      return parsed.map((e) => e is String ? e : '').toList(growable: false);
    } on FormatException {
      return const <String>[];
    }
  }

  static String? _encodeUsage(TokenUsage? usage) =>
      usage == null ? null : jsonEncode(usage.toJson());

  static TokenUsage? _decodeUsage(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return TokenUsage.fromJson(decoded.map((k, v) => MapEntry('$k', v)));
    } on FormatException {
      return null;
    }
  }

  static String? _encodeProgress(LongTaskProgress? progress) =>
      progress == null ? null : jsonEncode(progress.toJson());

  static LongTaskProgress? _decodeProgress(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return LongTaskProgress.fromJson(
        decoded.map((k, v) => MapEntry('$k', v)),
      );
    } on FormatException {
      return null;
    }
  }

  // ─── row decoders ─────────────────────────────────────────────────

  ChatSession _sessionFromRow(QueryRow row) {
    final lastMs = row.readNullable<int>('last_message_at');
    // Subquery columns are only present on list/find paths that SELECT them.
    final preview = _tryReadString(row, 'preview');
    final messageCount = _tryReadInt(row, 'message_count') ?? 0;
    return ChatSession(
      id: row.read<String>('id'),
      ownerUserId: row.read<String>('owner_user_id'),
      title: row.read<String>('title'),
      model: row.readNullable<String>('model'),
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        row.read<int>('created_at'),
        isUtc: true,
      ),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        row.read<int>('updated_at'),
        isUtc: true,
      ),
      lastMessageAt: lastMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(lastMs, isUtc: true),
      preview: preview == null || preview.trim().isEmpty ? null : preview.trim(),
      messageCount: messageCount,
      pinned: (_tryReadInt(row, 'pinned') ?? 0) != 0,
      archived: (_tryReadInt(row, 'archived') ?? 0) != 0,
    );
  }

  static String? _tryReadString(QueryRow row, String column) {
    try {
      return row.readNullable<String>(column);
    } on Object {
      return null;
    }
  }

  static int? _tryReadInt(QueryRow row, String column) {
    try {
      return row.readNullable<int>(column);
    } on Object {
      return null;
    }
  }

  ChatMessage _messageFromRow(QueryRow row) {
    final stopRaw = row.readNullable<String>('stop_reason');
    return ChatMessage(
      id: row.read<String>('id'),
      sessionId: row.read<String>('session_id'),
      ownerUserId: row.read<String>('owner_user_id'),
      role: ChatRoleX.parse(row.read<String>('role')),
      content: row.read<String>('content'),
      toolCalls: ToolInvocation.decodeList(
        row.readNullable<String>('tool_calls_json'),
      ),
      textSegments: _decodeTextSegments(
        row.readNullable<String>('text_segments_json'),
      ),
      status: ChatMessageStatusX.parse(row.read<String>('status')),
      errorMessage: row.readNullable<String>('error_message'),
      stopReason: stopRaw == null ? null : ChatStopReasonX.parse(stopRaw),
      reasoningText: row.readNullable<String>('reasoning_text'),
      usage: _decodeUsage(row.readNullable<String>('usage_json')),
      progress: _decodeProgress(row.readNullable<String>('progress_json')),
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        row.read<int>('created_at'),
        isUtc: true,
      ),
    );
  }
}
