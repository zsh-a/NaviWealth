import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../data/db/app_database.dart';
import '../../data/domain/hlc.dart';
import 'cursor_store.dart';
import 'op_outbox.dart';
import 'row_applier.dart' show kSyncPkOverrides;

/// Drift-backed [OutboxStore] over the `op_outbox` table.
///
/// v2 keeps `op_outbox` purely as a *dirty-pointer log*: the write path
/// (repositories) still enqueues an op per mutation, but the sync engine
/// only reads the `(table, row_id)` set out of it and pushes each row's
/// current state. `fields_diff` / `op_type` are no longer interpreted.
class DriftOutboxStore implements OutboxStore {
  DriftOutboxStore(this._db);
  final AppDatabase _db;

  @override
  Future<int> depth() async {
    final row = await _db
        .customSelect('SELECT COUNT(*) AS c FROM op_outbox')
        .getSingle();
    return row.read<int>('c');
  }

  @override
  Future<void> enqueue({required String table, required String rowId}) async {
    await _db.customStatement(
      'INSERT INTO op_outbox (op_id, table_name, row_id, created_at) '
      'VALUES (?, ?, ?, ?)',
      [
        const Uuid().v4(),
        table,
        rowId,
        DateTime.now().toUtc().toIso8601String(),
      ],
    );
  }
}

/// Reads `op_outbox` as the set of locally-dirty rows and serialises each
/// row's current state for push (`docs/sync-v2.md` §7.3).
class DriftPendingRows implements PendingRows {
  DriftPendingRows(this._db);
  final AppDatabase _db;

  @override
  Future<int> depth() async {
    final row = await _db
        .customSelect('SELECT COUNT(*) AS c FROM op_outbox')
        .getSingle();
    return row.read<int>('c');
  }

  /// All queued local mutations as `(opId, table, rowId)` pointers, oldest
  /// first. Multiple ops on the same row collapse to one push downstream.
  @override
  Future<List<PendingPointer>> pointers() async {
    final rows = await _db
        .customSelect(
          'SELECT op_id, table_name, row_id FROM op_outbox '
          'ORDER BY created_at ASC, op_id ASC',
        )
        .get();
    return rows
        .map(
          (r) => PendingPointer(
            opId: r.read<String>('op_id'),
            table: r.read<String>('table_name'),
            rowId: r.read<String>('row_id'),
          ),
        )
        .toList(growable: false);
  }

  /// Read a row's current state as a JSON-safe column → value map.
  ///
  /// Returns `null` if the row is gone — deletes are soft, so under normal
  /// operation the row always exists; a `null` means a stale pointer.
  @override
  Future<Map<String, Object?>?> readRow(String table, String rowId) async {
    final pk = kSyncPkOverrides[table] ?? 'id';
    final row = await _db
        .customSelect(
          'SELECT * FROM $table WHERE $pk = ?',
          variables: [Variable.withString(rowId)],
        )
        .getSingleOrNull();
    return row?.data;
  }

  /// Delete acknowledged op pointers. New ops queued mid-flight carry fresh
  /// `op_id`s and survive, so they are re-pushed on the next cycle.
  @override
  Future<void> clear(Iterable<String> opIds) async {
    final ids = opIds.toList(growable: false);
    if (ids.isEmpty) return;
    final placeholders = List.filled(ids.length, '?').join(',');
    await _db.customStatement(
      'DELETE FROM op_outbox WHERE op_id IN ($placeholders)',
      ids,
    );
  }
}

/// Drift-backed [CursorStore] over the `sync_meta` key/value table.
class DriftCursorStore implements CursorStore {
  DriftCursorStore(this._db);
  final AppDatabase _db;

  static const _kSeq = 'sync.cursor';
  static const _kLocalHlc = 'sync.local_hlc';

  @override
  Future<int> readSeq() async {
    final raw = await _readValue(_kSeq);
    return raw == null ? 0 : (int.tryParse(raw) ?? 0);
  }

  @override
  Future<void> writeSeq(int seq) => _writeValue(_kSeq, '$seq');

  @override
  Future<Hlc?> readLocalHlc() async {
    final raw = await _readValue(_kLocalHlc);
    return raw == null ? null : Hlc.parse(raw);
  }

  @override
  Future<void> writeLocalHlc(Hlc hlc) =>
      _writeValue(_kLocalHlc, hlc.toString());

  Future<String?> _readValue(String key) async {
    final rows = await _db
        .customSelect(
          'SELECT value FROM sync_meta WHERE key = ?',
          variables: [Variable.withString(key)],
        )
        .get();
    if (rows.isEmpty) return null;
    return rows.first.read<String>('value');
  }

  Future<void> _writeValue(String key, String value) async {
    await _db.customStatement(
      'INSERT INTO sync_meta(key, value) VALUES (?, ?) '
      'ON CONFLICT(key) DO UPDATE SET value = excluded.value',
      [key, value],
    );
  }
}

/// No-op [OutboxStore] used in local-only mode. All writes are dropped — the
/// user opted out of sync, so nothing should ever enter the outbox.
class NoopOutboxStore implements OutboxStore {
  const NoopOutboxStore();

  @override
  Future<int> depth() async => 0;

  @override
  Future<void> enqueue({required String table, required String rowId}) async {}
}

/// In-memory [OutboxStore] for tests.
class InMemoryOutboxStore implements OutboxStore {
  final List<({String table, String rowId})> items = [];

  @override
  Future<int> depth() async => items.length;

  @override
  Future<void> enqueue({required String table, required String rowId}) async {
    items.add((table: table, rowId: rowId));
  }
}

/// In-memory [CursorStore] for tests.
class InMemoryCursorStore implements CursorStore {
  int _seq = 0;
  Hlc? _localHlc;

  @override
  Future<int> readSeq() async => _seq;

  @override
  Future<void> writeSeq(int seq) async => _seq = seq;

  @override
  Future<Hlc?> readLocalHlc() async => _localHlc;

  @override
  Future<void> writeLocalHlc(Hlc hlc) async => _localHlc = hlc;
}
