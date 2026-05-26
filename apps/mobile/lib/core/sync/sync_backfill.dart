import 'package:drift/drift.dart';

import '../../core/persistence/app_database.dart';
import '../auth/auth_session.dart';
import 'op_outbox.dart';
import 'row_applier.dart' show kSyncPkOverrides;

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

  /// Bumped to force a re-enqueue. v2 bumps it because the v13 → v14
  /// migration drops `op_outbox`; re-running the pass repopulates it.
  static const version = '4';

  /// Tables to backfill. Order is irrelevant — v2 rows are independent.
  static const _tables = <String>[
    'accounts',
    'assets',
    'prices',
    'recurring_transactions',
    'journal_entries',
    'postings',
    'liabilities',
    'amortization_entries',
    'users',
    'settings',
    'categories',
    'tag_links',
  ];

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
    for (final table in _tables) {
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
    final pk = kSyncPkOverrides[table] ?? 'id';
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
