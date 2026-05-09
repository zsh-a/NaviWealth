import 'package:drift/drift.dart';

import '../../core/sync/op.dart';
import '../../core/sync/op_applier.dart';
import '../db/app_database.dart';
import '../domain/hlc.dart';

/// Schema-driven LWW applier for any syncable table.
///
/// Uses Drift's column metadata (`actualTableName` + `$columns`) to coerce
/// wire JSON values to the SQLite-native shape the Drift readers expect
/// (e.g. ISO-8601 timestamps → Unix seconds for `dateTime` columns,
/// `bool` → 0/1, `num` → int for INTEGER columns). Anything not on the
/// table's column list is dropped — the wire schema is the authoritative
/// surface, but unknown fields shouldn't break old clients.
///
/// Compared to a typed per-table applier this trades a small amount of
/// validation strictness for a single ~150-line implementation that covers
/// every synced table not handled by [AccountOpApplier].
class GenericLwwApplier implements OpApplier {
  GenericLwwApplier({
    required AppDatabase db,
    required String tableName,
    String pkColumn = 'id',
  }) : _db = db,
       _tableName = tableName,
       _pkColumn = pkColumn,
       _columnTypes = _columnTypeMap(db, tableName);

  final AppDatabase _db;
  final String _tableName;
  final String _pkColumn;
  final Map<String, DriftSqlType<Object>> _columnTypes;

  static Map<String, DriftSqlType<Object>> _columnTypeMap(
    AppDatabase db,
    String tableName,
  ) {
    final info = db.allTables.firstWhere(
      (t) => t.actualTableName == tableName,
      orElse: () => throw StateError('unknown drift table: $tableName'),
    );
    final map = <String, DriftSqlType<Object>>{};
    for (final c in info.$columns) {
      // BaseSqlType is sealed; only the built-in DriftSqlType variants need
      // coercion. Any custom user-defined types fall through as identity.
      final t = c.type;
      if (t is DriftSqlType<Object>) map[c.name] = t;
    }
    return map;
  }

  @override
  Future<void> applyAll(List<Op> ops) async {
    if (ops.isEmpty) return;
    await _db.transaction(() async {
      for (final op in ops) {
        if (op.tableName != _tableName) continue;
        await _apply(op);
      }
    });
  }

  Future<void> _apply(Op op) async {
    // LWW guard. Read whatever HLC is already on the row; if it's >= the
    // incoming op, the local state already reflects a newer-or-equal write.
    final existing = await _db
        .customSelect(
          'SELECT hlc FROM $_tableName WHERE $_pkColumn = ?',
          variables: [Variable.withString(op.rowId)],
        )
        .getSingleOrNull();
    if (existing != null) {
      final existingHlc = Hlc.parse(existing.read<String>('hlc'));
      if (existingHlc >= op.hlc) return;
    }

    final fields = op.fieldsDiff ?? const <String, Object?>{};

    switch (op.opType) {
      case OpType.insert:
        await _writeFullRow(op, fields);
      case OpType.update:
        // Skip orphan updates — wait for the matching insert on a future
        // cycle. Cursor only advances past ops we've actually applied.
        if (existing == null) return;
        await _writeUpdate(op, fields);
      case OpType.delete:
        // Skip never-seen tombstones; cleaner than synthesising a placeholder
        // row that violates NOT NULL constraints on the local schema.
        if (existing == null) return;
        await _writeDelete(op);
    }
  }

  Future<void> _writeFullRow(Op op, Map<String, Object?> fields) async {
    final ordered = <String, Object?>{...fields};
    ordered.putIfAbsent(_pkColumn, () => op.rowId);
    final cols = ordered.keys
        .where(_columnTypes.containsKey)
        .toList(growable: false);
    final placeholders = List.filled(cols.length, '?').join(', ');
    final sql =
        'INSERT OR REPLACE INTO $_tableName (${cols.join(', ')}) '
        'VALUES ($placeholders)';
    final args = cols.map((c) => _coerce(c, ordered[c])).toList();
    await _db.customStatement(sql, args);
  }

  Future<void> _writeUpdate(Op op, Map<String, Object?> fields) async {
    final cols = fields.keys
        .where((k) => _columnTypes.containsKey(k) && k != _pkColumn)
        .toList(growable: false);
    if (cols.isEmpty) return;
    final setClause = cols.map((c) => '$c = ?').join(', ');
    final sql = 'UPDATE $_tableName SET $setClause WHERE $_pkColumn = ?';
    final args = <Object?>[
      ...cols.map((c) => _coerce(c, fields[c])),
      op.rowId,
    ];
    await _db.customStatement(sql, args);
  }

  Future<void> _writeDelete(Op op) async {
    final wallSecs = op.hlc.wallTime.millisecondsSinceEpoch ~/ 1000;
    await _db.customStatement(
      'UPDATE $_tableName SET hlc = ?, updated_at = ?, updated_by_device = ?, '
      'deleted_at = ? WHERE $_pkColumn = ?',
      [op.hlc.toString(), wallSecs, op.deviceId, wallSecs, op.rowId],
    );
  }

  Object? _coerce(String column, Object? value) {
    if (value == null) return null;
    final type = _columnTypes[column];
    if (type == null) return value;
    switch (type) {
      case DriftSqlType.dateTime:
        if (value is String) {
          return DateTime.parse(value).millisecondsSinceEpoch ~/ 1000;
        }
        if (value is DateTime) return value.millisecondsSinceEpoch ~/ 1000;
        if (value is num) return value.toInt();
        return value;
      case DriftSqlType.bool:
        if (value is bool) return value ? 1 : 0;
        if (value is num) return value.toInt() == 0 ? 0 : 1;
        if (value is String) return value.toLowerCase() == 'true' ? 1 : 0;
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
