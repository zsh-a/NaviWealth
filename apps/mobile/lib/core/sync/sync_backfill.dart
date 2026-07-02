import 'package:drift/drift.dart';

import '../../core/persistence/app_database.dart';
import '../auth/auth_session.dart';
import 'op_outbox.dart';
import 'sync_table_registry.dart';

/// Queues one dirty-pointer per pre-existing local row, so a device that
/// accumulated data before sync was enabled (or before the v2 migration
/// wiped the outbox) still pushes everything.
///
/// Idempotent: a marker in `sync_meta` records that the pass ran for this
/// `(version, user, device)`.
class SyncBackfill {
  SyncBackfill({
    required AppDatabase db,
    required OutboxStore outbox,
    required AuthSession session,
  }) : _db = db,
       _outbox = outbox,
       _session = session;

  final AppDatabase _db;
  final OutboxStore _outbox;
  final AuthSession _session;

  /// Bumped to force a re-enqueue. v6 derives the table list from the sync
  /// registry and includes all owner-scoped sync tables.
  static const version = '6';

  /// Tables to backfill. Order is irrelevant — v2 rows are independent.
  /// Also used by [AuthController._migrateOwnerUserId] for mode switching.
  static final List<String> tables = kSyncBackfillTables;

  Future<int> enqueueMissingLocalRows() async {
    final key =
        'sync.backfill.$version.${_session.userId}.${_session.deviceId}';
    final existing = await _db
        .customSelect(
          'SELECT value FROM sync_meta WHERE key = ?',
          variables: [Variable.withString(key)],
        )
        .getSingleOrNull();
    if (existing != null) return 0;

    var queued = 0;
    for (final table in tables) {
      queued += await _backfillTable(table);
    }

    await _db.customStatement(
      'INSERT INTO sync_meta(key, value) VALUES (?, ?) '
      'ON CONFLICT(key) DO UPDATE SET value = excluded.value',
      [key, DateTime.now().toUtc().toIso8601String()],
    );
    return queued;
  }

  Future<int> _backfillTable(String table) async {
    final pk = syncPrimaryKeyForTable(table);
    // System accounts are seeded locally on every device — never sync them.
    final extra = table == 'accounts'
        ? " AND id NOT LIKE 'system-account:%'"
        : '';
    final rows = await _db
        .customSelect(
          'SELECT $pk AS row_id FROM $table '
          'WHERE owner_user_id = ? AND deleted_at IS NULL$extra',
          variables: [Variable.withString(_session.userId)],
        )
        .get();
    for (final r in rows) {
      await _outbox.enqueue(table: table, rowId: r.read<String>('row_id'));
    }
    return rows.length;
  }
}
