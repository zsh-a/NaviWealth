import 'package:drift/drift.dart';

import '../../data/db/app_database.dart';
import '../../data/domain/hlc.dart';
import 'sync_api_client.dart';

/// The closed set of tables that participate in sync (`docs/sync-v2.md` §4).
/// Adding a value is a data-model change only — the server's row store is
/// schema-agnostic.
const Set<String> kSyncableTables = {
  'accounts',
  'assets',
  'liabilities',
  'fx_rates',
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
};

/// Primary-key column for the tables whose PK is not `id`.
const Map<String, String> kSyncPkOverrides = {
  'settings': 'user_id',
  'options_strategy_profile': 'user_id',
};

/// Applies pulled row-states to the local Drift tables with per-row LWW
/// (`docs/sync-v2.md` §7.3).
///
/// Schema-agnostic: column shapes are read from Drift's runtime metadata,
/// so a new syncable table needs no applier change. This mirrors the
/// server's generic row store — one ~120-line class replaces v1's per-table
/// op-appliers.
class RowApplier {
  RowApplier(this._db);

  final AppDatabase _db;
  final Map<String, Map<String, DriftSqlType<Object>>> _typeCache = {};

  Map<String, DriftSqlType<Object>> _columnTypes(String table) {
    return _typeCache.putIfAbsent(table, () {
      final info = _db.allTables.firstWhere(
        (t) => t.actualTableName == table,
        orElse: () => throw StateError('unknown drift table: $table'),
      );
      final map = <String, DriftSqlType<Object>>{};
      for (final c in info.$columns) {
        final t = c.type;
        if (t is DriftSqlType<Object>) map[c.name] = t;
      }
      return map;
    });
  }

  /// Apply [rows] in a single transaction. Returns the count actually
  /// written (rows shadowed by newer-or-equal local state are skipped).
  Future<int> applyAll(List<RowChange> rows) async {
    if (rows.isEmpty) return 0;
    var written = 0;
    await _db.transaction(() async {
      // Cross-row references (posting → journal_entry) may arrive in any
      // order; defer FK checks to commit so the page applies atomically.
      await _db.customStatement('PRAGMA defer_foreign_keys = ON');
      for (final row in rows) {
        if (!kSyncableTables.contains(row.table)) continue;
        if (await _apply(row)) written++;
      }
    });
    return written;
  }

  Future<bool> _apply(RowChange row) async {
    final types = _columnTypes(row.table);
    final pk = kSyncPkOverrides[row.table] ?? 'id';

    // LWW guard — keep local state when its version is newer-or-equal.
    final existing = await _db
        .customSelect(
          'SELECT hlc FROM ${row.table} WHERE $pk = ?',
          variables: [Variable.withString(row.id)],
        )
        .getSingleOrNull();
    if (existing != null) {
      final localHlc = Hlc.parse(existing.read<String>('hlc'));
      final remoteHlc = Hlc.parse(row.version);
      if (localHlc >= remoteHlc) return false;
    }

    // Write the full row state. The payload already carries every column
    // (including `hlc`, `deleted_at`, `owner_user_id`) so a delete is just
    // a row whose `deleted_at` is set.
    final ordered = <String, Object?>{...?row.payload};
    ordered[pk] = row.id;
    ordered.putIfAbsent('hlc', () => row.version);
    final cols = ordered.keys.where(types.containsKey).toList(growable: false);
    if (cols.isEmpty) return false;
    final placeholders = List.filled(cols.length, '?').join(', ');
    final args = cols
        .map((c) => _coerce(types[c], ordered[c]))
        .toList(growable: false);
    await _db.customStatement(
      'INSERT OR REPLACE INTO ${row.table} (${cols.join(', ')}) '
      'VALUES ($placeholders)',
      args,
    );
    return true;
  }

  /// Coerce a JSON-decoded value to the SQLite-native shape Drift's readers
  /// expect. Push-side serialization already emits raw SQLite values, so
  /// this is near-identity; the dateTime/bool branches just absorb any
  /// JSON widening on the round trip.
  Object? _coerce(DriftSqlType<Object>? type, Object? value) {
    if (value == null || type == null) return value;
    switch (type) {
      case DriftSqlType.dateTime:
        if (value is String) {
          return DateTime.parse(value).millisecondsSinceEpoch ~/ 1000;
        }
        if (value is num) return value.toInt();
        return value;
      case DriftSqlType.bool:
        if (value is bool) return value ? 1 : 0;
        if (value is num) return value.toInt() == 0 ? 0 : 1;
        return value;
      case DriftSqlType.int:
      case DriftSqlType.bigInt:
        if (value is num) return value.toInt();
        return value;
      case DriftSqlType.double:
        if (value is num) return value.toDouble();
        return value;
      case DriftSqlType.string:
      case DriftSqlType.blob:
      case DriftSqlType.any:
        return value;
    }
  }
}
