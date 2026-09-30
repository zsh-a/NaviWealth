import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:naviwealth/core/sync/hlc.dart';

import '../../core/persistence/app_database.dart';
import '../logging/app_logger.dart';
import 'sync_api_client.dart';
import 'sync_payload_store.dart';
import 'sync_table_registry.dart';

/// Applies pulled row-states to the local Drift tables with per-row LWW
/// (`docs/sync/sync-v3.md`).
///
/// Schema-agnostic: column shapes are read from Drift's runtime metadata,
/// so a new syncable table needs no applier change. This mirrors the
/// server's generic row store. Local compatibility state preserves opaque
/// fields through mixed-version edits without adding business logic.
class RowApplier {
  RowApplier(
    this._db, {
    AppLogger? logger,
    String? ownerUserId,
    List<SyncTableRegistration> registrations = kSyncTableRegistrations,
  }) : _logger = logger ?? AppLogger.instance,
       _ownerUserId = ownerUserId,
       _payloads = SyncPayloadStore(_db),
       _registry = {
         for (final registration in registrations)
           registration.table: registration,
       };

  final AppDatabase _db;
  final AppLogger _logger;
  final String? _ownerUserId;
  final SyncPayloadStore _payloads;
  final Map<String, SyncTableRegistration> _registry;
  final Map<String, Map<String, DriftSqlType<Object>>> _typeCache = {};
  bool _allowEqualReplay = false;

  Future<Map<String, DriftSqlType<Object>>> _columnTypes(String table) async {
    final cached = _typeCache[table];
    if (cached != null) return cached;
    final actual = await _db.customSelect('PRAGMA table_info($table)').get();
    final names = actual.map((row) => row.read<String>('name')).toSet();
    final info = _db.allTables.firstWhere(
      (t) => t.actualTableName == table,
      orElse: () => throw StateError('unknown drift table: $table'),
    );
    final map = <String, DriftSqlType<Object>>{};
    for (final c in info.$columns) {
      final t = c.type;
      if (names.contains(c.name) && t is DriftSqlType<Object>) map[c.name] = t;
    }
    _typeCache[table] = map;
    return map;
  }

  /// Reset the cursor once when codec, namespace, PK or supported columns
  /// change. Re-pull is a current-state replay within Sync v3, not negotiation.
  /// Hydrate previously opaque fields before UI or dirty-row serialization can
  /// replace newly supported values with local defaults.
  Future<bool> prepareCompatibility() async {
    _typeCache.clear();
    final registrations = _registry.values.toList()
      ..sort((a, b) => a.table.compareTo(b.table));
    final prefixes = kSyncDomainPrefixes.toList()..sort();
    final shape = <Object?>['row-codec-8', prefixes];
    for (final registration in registrations) {
      final types = await _columnTypes(registration.table);
      final columns = types.keys.toList()..sort();
      shape.add([
        registration.table,
        registration.domainPrefix,
        registration.primaryKey,
        registration.ownerScoped,
        [
          for (final column in columns) [column, types[column].toString()],
        ],
      ]);
    }
    final signature = jsonEncode(shape);
    return _db.transaction(() async {
      final previous = await _db
          .customSelect(
            "SELECT value FROM sync_meta WHERE key = 'sync.schema_signature'",
          )
          .getSingleOrNull();
      if (previous?.read<String>('value') == signature) return false;
      final retained = await _db
          .customSelect('SELECT * FROM sync_row_extras')
          .get();
      for (final row in retained) {
        final table = row.read<String>('table_name');
        if (!_registry.containsKey(table)) continue;
        final id = row.read<String>('row_id');
        final owner = row.read<String>('owner_user_id');
        final extras = await _payloads.extras(table, id, owner);
        final types = await _columnTypes(table);
        final supported = extras.keys.where(types.containsKey).toList();
        if (supported.isEmpty) continue;
        final pk = _registry[table]!.primaryKey;
        final ownerWhere = _registry[table]!.ownerScoped
            ? ' AND owner_user_id = ?'
            : '';
        await _db.customStatement(
          'UPDATE $table SET ${supported.map((c) => '$c = ?').join(', ')} '
          'WHERE $pk = ?$ownerWhere',
          [
            for (final c in supported) _coerce(types[c], extras[c]),
            id,
            if (ownerWhere.isNotEmpty) owner,
          ],
        );
        for (final key in supported) {
          extras.remove(key);
        }
        await _payloads.writeExtras(table, id, owner, extras);
      }
      await _db.customStatement(
        "DELETE FROM sync_meta WHERE key = 'sync.cursor'",
      );
      await _db.customStatement(
        'INSERT INTO sync_meta(key, value) VALUES (?, ?) '
        'ON CONFLICT(key) DO UPDATE SET value = excluded.value',
        ['sync.schema_signature', signature],
      );
      await _db.customStatement(
        "INSERT OR REPLACE INTO sync_meta(key, value) VALUES ('sync.schema_replay', '1')",
      );
      return true;
    });
  }

  /// Clear only after the engine durably drains the entire current-state pull.
  /// A crash or partial pull keeps equal-version hydration enabled on restart.
  Future<void> finishCompatibilityReplay() => _db.customStatement(
    "DELETE FROM sync_meta WHERE key = 'sync.schema_replay'",
  );

  String _owner(RowChange row) =>
      _ownerUserId ?? row.payload?['owner_user_id'] as String? ?? '';

  Future<bool> _localWins(RowChange row, String table) async {
    final pk = _registry[table]!.primaryKey;
    final scoped = _registry[table]!.ownerScoped;
    if (scoped &&
        _ownerUserId != null &&
        row.payload?['owner_user_id'] != _ownerUserId) {
      throw StateError('Sync row owner mismatch');
    }
    final existing = await _db
        .customSelect(
          'SELECT hlc${scoped ? ', owner_user_id' : ''} FROM $table WHERE $pk = ?',
          variables: [Variable(row.id)],
        )
        .getSingleOrNull();
    if (existing == null) return false;
    if (scoped && existing.read<String>('owner_user_id') != _owner(row)) {
      throw StateError('Sync row identity belongs to another owner');
    }
    final comparison = Hlc.parse(existing.read<String>('hlc'))
        .compareTo(Hlc.parse(row.version));
    return comparison > 0 || (comparison == 0 && !_allowEqualReplay);
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
    _allowEqualReplay =
        (await _db
            .customSelect(
              "SELECT 1 FROM sync_meta WHERE key = 'sync.schema_replay'",
            )
            .getSingleOrNull()) !=
        null;
    var written = 0;
    var skippedLocalWins = 0;
    var skippedUnknownDomain = 0;
    var skippedUnsupportedTable = 0;
    var skippedEmptyPayload = 0;
    await _db.transaction(() async {
      await _db.customStatement('PRAGMA defer_foreign_keys = ON');
      for (final row in rows) {
        final local = _resolveLocalTable(row.table);
        switch (local.outcome) {
          case _ResolveOutcome.ok:
            if (row.payload == null || row.payload!.isEmpty) {
              skippedEmptyPayload++;
            } else if (await _localWins(row, local.table!)) {
              skippedLocalWins++;
            } else {
              await _apply(row, local.table!);
              written++;
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
    final registration = _registry[stripped];
    if (registration == null ||
        wireTable != '${registration.domainPrefix}$stripped') {
      return const _ResolvedTable(_ResolveOutcome.unsupportedTable);
    }
    return _ResolvedTable(_ResolveOutcome.ok, table: stripped);
  }

  Future<void> _apply(RowChange row, String table) async {
    final types = await _columnTypes(table);
    final pk = _registry[table]!.primaryKey;

    // Write the full row state. The payload already carries every column
    // (including `hlc`, `deleted_at`, `owner_user_id`) so a delete is just
    // a row whose `deleted_at` is set.
    final ordered = <String, Object?>{...?row.payload};
    ordered[pk] = row.id;
    ordered['hlc'] = row.version;
    final cols = ordered.keys.where(types.containsKey).toList(growable: false);
    final placeholders = List.filled(cols.length, '?').join(', ');
    final args = cols
        .map((c) => _coerce(types[c], ordered[c]))
        .toList(growable: false);
    await _db.customStatement(
      'INSERT INTO $table (${cols.join(', ')}) VALUES ($placeholders) '
      'ON CONFLICT($pk) DO UPDATE SET '
      '${cols.where((c) => c != pk).map((c) => '$c = excluded.$c').join(', ')}',
      args,
    );
    final extras = await _payloads.extras(table, row.id, _owner(row));
    extras.removeWhere((key, _) => types.containsKey(key));
    extras.addAll(
      Map<String, Object?>.fromEntries(
        ordered.entries.where((entry) => !types.containsKey(entry.key)),
      ),
    );
    await _payloads.writeExtras(table, row.id, _owner(row), extras);
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
