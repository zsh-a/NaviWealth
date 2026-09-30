import 'package:drift/drift.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:uuid/uuid.dart';

import '../../core/persistence/app_database.dart';
import '../auth/domain_scope.dart';
import 'cursor_store.dart';
import 'domain_generation.dart';
import 'op_outbox.dart';
import 'sync_payload_store.dart';
import 'sync_table_registry.dart';

/// Drift-backed [OutboxStore] over the `op_outbox` table.
///
/// v3 keeps `op_outbox` purely as a *dirty-pointer log*: the write path
/// (repositories) still enqueues an op per mutation, but the sync engine
/// only reads the `(table, row_id)` set out of it and pushes each row's
/// current state. `fields_diff` / `op_type` are no longer interpreted.
class DriftOutboxStore implements OutboxStore {
  DriftOutboxStore(this._db);
  final AppDatabase _db;

  bool isBoundTo(AppDatabase database) => identical(_db, database);

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

/// Whether [outbox] is safe to use inside a repository transaction for
/// [database]. Cloud mode requires the Drift-backed outbox to share the exact
/// connection. Local-only mode deliberately uses [NoopOutboxStore]; it has no
/// external state and is therefore transaction-safe without a DB binding.
bool isOutboxBoundToDatabase(OutboxStore outbox, AppDatabase database) =>
    outbox is NoopOutboxStore ||
    (outbox is DriftOutboxStore && outbox.isBoundTo(database));

/// Reads `op_outbox` as the set of locally-dirty rows and serialises each
/// row's current state for push (`docs/sync/sync-v3.md`).
class DriftPendingRows implements PendingRows {
  DriftPendingRows(this._db, {String? ownerUserId})
    : _ownerUserId = ownerUserId;
  final AppDatabase _db;
  final String? _ownerUserId;

  @override
  Future<int> depth() async {
    if (_ownerUserId != null) return (await pointers()).length;
    final row = await _db
        .customSelect('SELECT COUNT(*) AS c FROM op_outbox')
        .getSingle();
    return row.read<int>('c');
  }

  /// Queued local mutations for this owner, oldest first. Foreign-owner rows
  /// remain queued; they must not be classified as missing rows and discarded.
  /// Orphan pointers still reach the engine for normal stale-pointer cleanup.
  @override
  Future<List<PendingPointer>> pointers() async {
    final rows = await _db
        .customSelect(
          'SELECT op_id, table_name, row_id FROM op_outbox '
          'ORDER BY created_at ASC, op_id ASC',
        )
        .get();
    final foreignOps = <String>{};
    if (_ownerUserId != null) {
      for (final table
          in rows.map((r) => r.read<String>('table_name')).toSet()) {
        final registration = kSyncTableRegistry[table];
        if (registration == null || !registration.ownerScoped) continue;
        final foreign = await _db
            .customSelect(
              'SELECT o.op_id FROM op_outbox o JOIN $table s '
              'ON s.${registration.primaryKey} = o.row_id '
              'WHERE o.table_name = ? AND s.owner_user_id != ?',
              variables: [Variable(table), Variable(_ownerUserId)],
            )
            .get();
        foreignOps.addAll(foreign.map((r) => r.read<String>('op_id')));
      }
    }
    return rows
        .where((r) => !foreignOps.contains(r.read<String>('op_id')))
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
  /// operation the row always exists. Foreign-owner rows are also withheld;
  /// [pointers] excludes their dirty work so it is not cleared as stale.
  @override
  Future<Map<String, Object?>?> readRow(String table, String rowId) async {
    if (!kSyncableTables.contains(table)) return null;
    final pk = syncPrimaryKeyForTable(table);
    final row = await _db
        .customSelect(
          'SELECT * FROM $table WHERE $pk = ?',
          variables: [Variable.withString(rowId)],
        )
        .getSingleOrNull();
    if (row == null) return null;
    final owner = _ownerUserId ?? row.data['owner_user_id'] as String? ?? '';
    if (kSyncTableRegistry[table]!.ownerScoped &&
        row.data['owner_user_id'] != owner) {
      return null;
    }
    return <String, Object?>{
      ...await SyncPayloadStore(_db).extras(table, rowId, owner),
      ...row.data,
    };
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

class DriftDomainGenerationStore implements DomainGenerationStore {
  DriftDomainGenerationStore(this._db, {required String ownerUserId})
    : _ownerUserId = ownerUserId;

  final AppDatabase _db;
  final String _ownerUserId;

  String _key(String domain) => 'sync.domain_generation.$_ownerUserId.$domain';

  @override
  Future<Map<String, int>> readAll() async {
    final values = <String, int>{};
    for (final scope in DomainScope.values) {
      final row = await _db
          .customSelect(
            'SELECT value FROM sync_meta WHERE key = ?',
            variables: <Variable<Object>>[Variable<Object>(_key(scope.wire))],
          )
          .getSingleOrNull();
      if (row != null) {
        values[scope.wire] = int.tryParse(row.read<String>('value')) ?? 0;
      }
    }
    return values;
  }

  @override
  Future<void> write(String domain, int generation) async {
    await _db.customStatement(
      'INSERT INTO sync_meta(key, value) VALUES (?, ?) '
      'ON CONFLICT(key) DO UPDATE SET value = excluded.value',
      [_key(domain), '$generation'],
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
