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

  /// Bumped to force a re-enqueue. v5 adds missing syncable tables
  /// (fx_rates, tags, budgets, goals, devices, watchlist_items,
  /// options_*, knowledge_*) and removes phantom `recurring_transactions`.
  static const version = '5';

  /// Tables to backfill. Must match `kSyncableTables` in `row_applier.dart`.
  /// Order is irrelevant — v2 rows are independent.
  /// Tables to backfill. Must match `kSyncableTables` in `row_applier.dart`,
  /// minus tables that lack the `SyncableTable` mixin (e.g. `fx_rates`).
  /// Also used by [AuthController._migrateOwnerUserId] for mode switching.
  static const tables = <String>[
    'accounts',
    'assets',
    'liabilities',
    // `fx_rates` intentionally excluded — no `owner_user_id` column.
    'tags',
    'budgets',
    'goals',
    'devices',
    'amortization_entries',
    'tag_links',
    'categories',
    'settings',
    'users',
    'journal_entries',
    'postings',
    'prices',
    'watchlist_items',
    'options_strategy_profile',
    'approved_underlyings',
    'options_trade_journal',
    'knowledge_notes',
    'knowledge_principles',
    'knowledge_assumptions',
    'knowledge_decisions',
    'knowledge_concepts',
    'knowledge_experiments',
    'knowledge_routines',
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
