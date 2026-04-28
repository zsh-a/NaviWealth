import 'dart:convert';

import 'package:drift/drift.dart';

import '../../data/db/app_database.dart';
import '../../data/domain/hlc.dart';
import 'cursor_store.dart';
import 'op.dart';
import 'op_outbox.dart';

/// Drift-backed implementation of [OutboxStore] using the v3 `op_outbox`
/// table created in `core/db/migrations.dart`.
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
  Future<void> enqueue(Op op) async {
    await _db.customStatement(
      'INSERT OR IGNORE INTO op_outbox '
      '(op_id, hlc_text, device_id, table_name, row_id, op_type, '
      ' fields_diff, created_at, attempts) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0)',
      [
        op.opId,
        op.hlc.toString(),
        op.deviceId,
        op.tableName,
        op.rowId,
        op.opType.wire,
        op.fieldsDiff == null ? null : jsonEncode(op.fieldsDiff),
        DateTime.now().toUtc().toIso8601String(),
      ],
    );
  }

  @override
  Future<List<Op>> peekBatch({
    int maxOps = 500,
    int maxBytes = 1024 * 1024,
  }) async {
    final rows = await _db
        .customSelect(
          'SELECT op_id, hlc_text, device_id, table_name, row_id, op_type, '
          '       fields_diff '
          'FROM op_outbox '
          'ORDER BY hlc_text ASC, created_at ASC '
          'LIMIT ?',
          variables: [Variable.withInt(maxOps)],
        )
        .get();

    final result = <Op>[];
    var bytes = 0;
    for (final r in rows) {
      final encoded = r.read<String?>('fields_diff');
      Map<String, Object?>? fieldsDiff;
      if (encoded != null) {
        final decoded = jsonDecode(encoded);
        if (decoded is Map) {
          fieldsDiff = decoded.map((k, v) => MapEntry(k as String, v));
        }
      }
      final op = Op(
        opId: r.read<String>('op_id'),
        tableName: r.read<String>('table_name'),
        rowId: r.read<String>('row_id'),
        opType: parseOpType(r.read<String>('op_type')),
        fieldsDiff: fieldsDiff,
        hlc: Hlc.parse(r.read<String>('hlc_text')),
        deviceId: r.read<String>('device_id'),
      );
      // Always include at least one op so a single oversized payload
      // can still be reported (server returns per-op `payload_too_large`).
      if (result.isNotEmpty && bytes + op.encodedSizeBytes > maxBytes) {
        break;
      }
      result.add(op);
      bytes += op.encodedSizeBytes;
    }
    return result;
  }

  @override
  Future<void> ack(Iterable<String> opIds) async {
    if (opIds.isEmpty) return;
    final ids = opIds.toList(growable: false);
    final placeholders = List.filled(ids.length, '?').join(',');
    await _db.customStatement(
      'DELETE FROM op_outbox WHERE op_id IN ($placeholders)',
      ids,
    );
  }

  @override
  Future<void> recordFailure({
    required String opId,
    required String code,
    String? message,
    String? payload,
  }) async {
    await _db.transaction(() async {
      await _db.customStatement(
        'INSERT INTO sync_errors (op_id, code, message, payload, recorded_at) '
        'VALUES (?, ?, ?, ?, ?)',
        [
          opId,
          code,
          message,
          payload,
          DateTime.now().toUtc().toIso8601String(),
        ],
      );
      await _db.customStatement('DELETE FROM op_outbox WHERE op_id = ?', [
        opId,
      ]);
    });
  }

  @override
  Future<void> bumpAttempts(Iterable<String> opIds) async {
    if (opIds.isEmpty) return;
    final ids = opIds.toList(growable: false);
    final placeholders = List.filled(ids.length, '?').join(',');
    await _db.customStatement(
      'UPDATE op_outbox SET attempts = attempts + 1 '
      'WHERE op_id IN ($placeholders)',
      ids,
    );
  }
}

/// Drift-backed [CursorStore] using the v3 `sync_meta` key/value table.
class DriftCursorStore implements CursorStore {
  DriftCursorStore(this._db);
  final AppDatabase _db;

  static const _kCursor = 'sync.cursor';
  static const _kLocalHlc = 'sync.local_hlc';

  @override
  Future<Hlc?> readCursor() => _readHlc(_kCursor);

  @override
  Future<void> writeCursor(Hlc hlc) => _writeHlc(_kCursor, hlc);

  @override
  Future<Hlc?> readLocalHlc() => _readHlc(_kLocalHlc);

  @override
  Future<void> writeLocalHlc(Hlc hlc) => _writeHlc(_kLocalHlc, hlc);

  Future<Hlc?> _readHlc(String key) async {
    final rows = await _db
        .customSelect(
          'SELECT value FROM sync_meta WHERE key = ?',
          variables: [Variable.withString(key)],
        )
        .get();
    if (rows.isEmpty) return null;
    final raw = rows.first.read<String>('value');
    return Hlc.parse(raw);
  }

  Future<void> _writeHlc(String key, Hlc hlc) async {
    await _db.customStatement(
      'INSERT INTO sync_meta(key, value) VALUES (?, ?) '
      'ON CONFLICT(key) DO UPDATE SET value = excluded.value',
      [key, hlc.toString()],
    );
  }
}

/// In-memory [OutboxStore] for tests. Mirrors the FIFO ordering the Drift
/// implementation enforces via `ORDER BY hlc_text ASC`.
class InMemoryOutboxStore implements OutboxStore {
  final List<Op> _items = [];
  final List<({String opId, String code, String? message})> failures = [];

  @override
  Future<int> depth() async => _items.length;

  @override
  Future<void> enqueue(Op op) async {
    if (_items.any((o) => o.opId == op.opId)) return;
    _items.add(op);
    _items.sort((a, b) {
      final c = a.hlc.toString().compareTo(b.hlc.toString());
      return c;
    });
  }

  @override
  Future<List<Op>> peekBatch({
    int maxOps = 500,
    int maxBytes = 1024 * 1024,
  }) async {
    final out = <Op>[];
    var bytes = 0;
    for (final op in _items) {
      if (out.length >= maxOps) break;
      if (out.isNotEmpty && bytes + op.encodedSizeBytes > maxBytes) break;
      out.add(op);
      bytes += op.encodedSizeBytes;
    }
    return out;
  }

  @override
  Future<void> ack(Iterable<String> opIds) async {
    final set = opIds.toSet();
    _items.removeWhere((o) => set.contains(o.opId));
  }

  @override
  Future<void> recordFailure({
    required String opId,
    required String code,
    String? message,
    String? payload,
  }) async {
    failures.add((opId: opId, code: code, message: message));
    _items.removeWhere((o) => o.opId == opId);
  }

  @override
  Future<void> bumpAttempts(Iterable<String> opIds) async {}
}

/// In-memory [CursorStore] for tests.
class InMemoryCursorStore implements CursorStore {
  Hlc? _cursor;
  Hlc? _localHlc;

  @override
  Future<Hlc?> readCursor() async => _cursor;

  @override
  Future<void> writeCursor(Hlc hlc) async => _cursor = hlc;

  @override
  Future<Hlc?> readLocalHlc() async => _localHlc;

  @override
  Future<void> writeLocalHlc(Hlc hlc) async => _localHlc = hlc;
}
