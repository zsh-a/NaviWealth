import 'package:drift/drift.dart';
import 'package:naviwealth/core/sync/hlc.dart';

import '../../core/persistence/app_database.dart';
import '../logging/app_logger.dart';
import 'sync_api_client.dart';
import 'sync_table_registry.dart';

/// Applies pulled row-states to the local Drift tables with per-row LWW
/// (`docs/sync/sync-v2.md` §7.3).
///
/// Schema-agnostic: column shapes are read from Drift's runtime metadata,
/// so a new syncable table needs no applier change. This mirrors the
/// server's generic row store — one ~120-line class replaces v1's per-table
/// op-appliers.
class RowApplier {
  RowApplier(this._db, {AppLogger? logger})
    : _logger = logger ?? AppLogger.instance;

  final AppDatabase _db;
  final AppLogger _logger;
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
    return (await applyWithReport(rows)).written;
  }

  /// Apply [rows] and keep enough skip detail for sync diagnostics. The
  /// write path still uses LWW; this report only makes that decision visible
  /// to the engine and settings page.
  Future<RowApplyReport> applyWithReport(List<RowChange> rows) async {
    if (rows.isEmpty) return const RowApplyReport.empty();
    var written = 0;
    var skippedLocalWins = 0;
    var skippedUnknownDomain = 0;
    var skippedUnsupportedTable = 0;
    var skippedEmptyPayload = 0;
    await _db.transaction(() async {
      // Cross-row references (posting → journal_entry) may arrive in any
      // order; defer FK checks to commit so the page applies atomically.
      await _db.customStatement('PRAGMA defer_foreign_keys = ON');
      for (final row in rows) {
        final local = _resolveLocalTable(row.table);
        switch (local.outcome) {
          case _ResolveOutcome.ok:
            final outcome = await _apply(row, local.table!);
            switch (outcome) {
              case _ApplyOutcome.written:
                written++;
              case _ApplyOutcome.localWins:
                skippedLocalWins++;
              case _ApplyOutcome.emptyPayload:
                skippedEmptyPayload++;
            }
          case _ResolveOutcome.unknownDomain:
            skippedUnknownDomain++;
          case _ResolveOutcome.unsupportedTable:
            skippedUnsupportedTable++;
        }
      }
    });
    return RowApplyReport(
      attempted: rows.length,
      written: written,
      skippedLocalWins: skippedLocalWins,
      skippedUnknownDomain: skippedUnknownDomain,
      skippedUnsupportedTable: skippedUnsupportedTable,
      skippedEmptyPayload: skippedEmptyPayload,
    );
  }

  /// Strip the LifeOS domain prefix and confirm the resulting table is
  /// syncable on this device. D-1.4 onward every wire row should carry a
  /// prefix; a row without one is treated as an unknown sender and
  /// dropped (legacy rows are migrated server-side in
  /// `0018_sync_row_namespace.sql`).
  _ResolvedTable _resolveLocalTable(String wireTable) {
    final stripped = stripDomainPrefix(wireTable);
    if (stripped == null) {
      _logger.w('sync: dropping row with unknown domain prefix: $wireTable');
      return const _ResolvedTable(_ResolveOutcome.unknownDomain);
    }
    if (!kSyncableTables.contains(stripped)) {
      return const _ResolvedTable(_ResolveOutcome.unsupportedTable);
    }
    return _ResolvedTable(_ResolveOutcome.ok, table: stripped);
  }

  Future<_ApplyOutcome> _apply(RowChange row, String table) async {
    final types = _columnTypes(table);
    final pk = syncPrimaryKeyForTable(table);

    // LWW guard — keep local state when its version is newer-or-equal.
    final existing = await _db
        .customSelect(
          'SELECT hlc FROM $table WHERE $pk = ?',
          variables: [Variable.withString(row.id)],
        )
        .getSingleOrNull();
    if (existing != null) {
      final localHlc = Hlc.parse(existing.read<String>('hlc'));
      final remoteHlc = Hlc.parse(row.version);
      if (localHlc >= remoteHlc) return _ApplyOutcome.localWins;
    }

    // Write the full row state. The payload already carries every column
    // (including `hlc`, `deleted_at`, `owner_user_id`) so a delete is just
    // a row whose `deleted_at` is set.
    final ordered = <String, Object?>{...?row.payload};
    ordered[pk] = row.id;
    ordered.putIfAbsent('hlc', () => row.version);
    final cols = ordered.keys.where(types.containsKey).toList(growable: false);
    if (cols.isEmpty) return _ApplyOutcome.emptyPayload;
    final placeholders = List.filled(cols.length, '?').join(', ');
    final args = cols
        .map((c) => _coerce(types[c], ordered[c]))
        .toList(growable: false);
    await _db.customStatement(
      'INSERT OR REPLACE INTO $table (${cols.join(', ')}) '
      'VALUES ($placeholders)',
      args,
    );
    return _ApplyOutcome.written;
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

class RowApplyReport {
  const RowApplyReport({
    required this.attempted,
    required this.written,
    required this.skippedLocalWins,
    required this.skippedUnknownDomain,
    required this.skippedUnsupportedTable,
    required this.skippedEmptyPayload,
  });

  const RowApplyReport.empty()
    : attempted = 0,
      written = 0,
      skippedLocalWins = 0,
      skippedUnknownDomain = 0,
      skippedUnsupportedTable = 0,
      skippedEmptyPayload = 0;

  final int attempted;
  final int written;
  final int skippedLocalWins;
  final int skippedUnknownDomain;
  final int skippedUnsupportedTable;
  final int skippedEmptyPayload;

  int get skippedIgnored =>
      skippedUnknownDomain + skippedUnsupportedTable + skippedEmptyPayload;

  RowApplyReport merge(RowApplyReport other) {
    return RowApplyReport(
      attempted: attempted + other.attempted,
      written: written + other.written,
      skippedLocalWins: skippedLocalWins + other.skippedLocalWins,
      skippedUnknownDomain: skippedUnknownDomain + other.skippedUnknownDomain,
      skippedUnsupportedTable:
          skippedUnsupportedTable + other.skippedUnsupportedTable,
      skippedEmptyPayload: skippedEmptyPayload + other.skippedEmptyPayload,
    );
  }
}

enum _ResolveOutcome { ok, unknownDomain, unsupportedTable }

class _ResolvedTable {
  const _ResolvedTable(this.outcome, {this.table});

  final _ResolveOutcome outcome;
  final String? table;
}

enum _ApplyOutcome { written, localWins, emptyPayload }
