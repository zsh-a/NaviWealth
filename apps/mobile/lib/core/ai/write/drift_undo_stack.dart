/// Wave 24 — Drift-backed undo stack for AI-driven local writes.
///
/// Today [LocalImmediateWriteExecutor] keeps undo entries in process
/// memory as `Future<void> Function()` closures; that's fine when the
/// 30-second window is shorter than a typical session, but a process
/// exit drops outstanding undos. The Drift table `ai_undo_stack` lets
/// us persist a structured *reversal description* across restarts.
///
/// Closures don't serialise; the persistable shape stores `kind` +
/// `payload` (JSON). On `undo` the caller looks up the matching
/// reverter implementation by `kind`, hands it the payload, and lets
/// it construct + run the inverse mutation.
///
/// This module is intentionally storage-only — the executor refactor
/// to consult both an in-memory ring AND the persistent stack lives
/// in a follow-up wave. Storing the primitive first means future
/// callers that need durability can adopt it without changing the
/// API for callers that don't.
library;

import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../data/db/app_database.dart';

class PersistedUndoEntry {
  const PersistedUndoEntry({
    required this.token,
    required this.kind,
    required this.payload,
    required this.createdAt,
    required this.expiresAt,
  });

  /// Stable identifier the caller uses to look up + consume.
  final String token;

  /// Discriminator for the reverter implementation (e.g. `memo_edit`).
  final String kind;

  /// Information the reverter needs to construct the inverse mutation.
  /// JSON-encodable.
  final Map<String, Object?> payload;

  final DateTime createdAt;

  /// `null` means no expiry (caller must prune explicitly).
  final DateTime? expiresAt;
}

class DriftUndoStack {
  DriftUndoStack(this._db, {this.ownerUserId});

  final AppDatabase _db;
  final String? ownerUserId;

  String get _owner => ownerUserId ?? '';

  /// Wave 35 — manual change-notify channel. The Drift `customSelect`
  /// stream API can't auto-track tables created via `customStatement`
  /// (no `TableInfo`), so each mutation calls [_notifyChange] and the
  /// [watchAll] stream re-fetches.
  final StreamController<void> _changes = StreamController<void>.broadcast();

  void _notifyChange() {
    if (!_changes.isClosed) _changes.add(null);
  }

  void dispose() {
    _changes.close();
  }

  /// Persist a new entry. Token uniqueness is the caller's
  /// responsibility — duplicate tokens cause an `INSERT OR REPLACE`
  /// (the new payload wins).
  Future<void> put(PersistedUndoEntry entry) async {
    await _db.customInsert(
      'INSERT OR REPLACE INTO ai_undo_stack '
      '(token, owner_user_id, created_at_iso, expires_at_iso, kind, payload_json) '
      'VALUES (?1, ?2, ?3, ?4, ?5, ?6)',
      variables: [
        Variable.withString(entry.token),
        Variable.withString(_owner),
        Variable.withString(entry.createdAt.toUtc().toIso8601String()),
        if (entry.expiresAt != null)
          Variable.withString(entry.expiresAt!.toUtc().toIso8601String())
        else
          const Variable<String>(null),
        Variable.withString(entry.kind),
        Variable.withString(jsonEncode(entry.payload)),
      ],
    );
    _notifyChange();
  }

  /// Atomically read + remove the entry for [token]. Returns `null`
  /// when there is no matching row (the entry was undone already, or
  /// pruned, or never existed).
  ///
  /// Uses a transaction so concurrent `take(...)` calls from two
  /// undo-button taps can't both win.
  Future<PersistedUndoEntry?> take(String token) async {
    return _db.transaction(() async {
      final rows = await _db
          .customSelect(
            'SELECT token, created_at_iso, expires_at_iso, kind, payload_json '
            'FROM ai_undo_stack '
            'WHERE token = ?1 AND owner_user_id = ?2',
            variables: [
              Variable.withString(token),
              Variable.withString(_owner),
            ],
          )
          .get();
      if (rows.isEmpty) return null;
      final row = rows.first;
      await _db.customStatement(
        'DELETE FROM ai_undo_stack WHERE token = ?1 AND owner_user_id = ?2',
        [token, _owner],
      );
      final entry = _rowToEntry(row);
      _notifyChange();
      return entry;
    });
  }

  /// Snapshot of currently-persisted entries, newest first.
  Future<List<PersistedUndoEntry>> all({int limit = 100}) async {
    final rows = await _db
        .customSelect(
          'SELECT token, created_at_iso, expires_at_iso, kind, payload_json '
          'FROM ai_undo_stack '
          'WHERE owner_user_id = ?1 '
          'ORDER BY created_at_iso DESC '
          'LIMIT ?2',
          variables: [Variable.withString(_owner), Variable.withInt(limit)],
        )
        .get();
    return rows.map(_rowToEntry).toList(growable: false);
  }

  /// Drop entries whose `expires_at_iso` is set AND strictly before
  /// [cutoff]. Rows without an expiry are preserved (caller's choice).
  Future<void> pruneExpiredBefore(DateTime cutoff) async {
    await _db.customStatement(
      'DELETE FROM ai_undo_stack '
      'WHERE owner_user_id = ?1 '
      '  AND expires_at_iso IS NOT NULL '
      '  AND expires_at_iso < ?2',
      [_owner, cutoff.toUtc().toIso8601String()],
    );
    _notifyChange();
  }

  /// Wave 35 — stream the current entry list (newest first). Emits an
  /// initial snapshot and re-fetches after every mutation routed
  /// through this stack instance.
  Stream<List<PersistedUndoEntry>> watchAll({int limit = 100}) async* {
    yield await all(limit: limit);
    await for (final _ in _changes.stream) {
      yield await all(limit: limit);
    }
  }

  PersistedUndoEntry _rowToEntry(QueryRow row) {
    final raw = row.read<String>('payload_json');
    final payload = jsonDecode(raw) as Map<String, Object?>;
    final expiresIso = row.readNullable<String>('expires_at_iso');
    return PersistedUndoEntry(
      token: row.read<String>('token'),
      kind: row.read<String>('kind'),
      payload: payload,
      createdAt: DateTime.parse(row.read<String>('created_at_iso')).toUtc(),
      expiresAt: expiresIso == null ? null : DateTime.parse(expiresIso).toUtc(),
    );
  }
}
