import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/op.dart';
import 'package:naviwealth/data/domain/hlc.dart';

import '../../data/db/test_database.dart';

Op makeOp({
  required String id,
  required int wall,
  OpType type = OpType.update,
}) {
  return Op(
    opId: id,
    tableName: 'accounts',
    rowId: 'A-$id',
    opType: type,
    fieldsDiff: type == OpType.delete ? null : {'name': 'n-$id'},
    hlc: Hlc(wallMillis: wall, counter: 0, nodeId: 'dev'),
    deviceId: 'dev',
  );
}

void main() {
  group('DriftOutboxStore', () {
    test('enqueue is idempotent on op_id', () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final outbox = DriftOutboxStore(db);
      final op = makeOp(id: '1', wall: 1_000_000_000_000);
      await outbox.enqueue(op);
      await outbox.enqueue(op);
      expect(await outbox.depth(), 1);
    });

    test('peekBatch returns ops in HLC order', () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final outbox = DriftOutboxStore(db);
      await outbox.enqueue(makeOp(id: 'b', wall: 1_500_000_000_001));
      await outbox.enqueue(makeOp(id: 'a', wall: 1_500_000_000_000));
      final batch = await outbox.peekBatch();
      expect(batch.map((o) => o.opId).toList(), ['a', 'b']);
    });

    test('ack removes the rows', () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final outbox = DriftOutboxStore(db);
      await outbox.enqueue(makeOp(id: '1', wall: 1_500_000_000_000));
      await outbox.enqueue(makeOp(id: '2', wall: 1_500_000_000_001));
      await outbox.ack(['1']);
      expect(await outbox.depth(), 1);
      final remaining = await outbox.peekBatch();
      expect(remaining.single.opId, '2');
    });

    test('recordFailure removes from outbox + writes sync_errors', () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final outbox = DriftOutboxStore(db);
      await outbox.enqueue(makeOp(id: '1', wall: 1_500_000_000_000));
      await outbox.recordFailure(opId: '1', code: 'op_id_mutated');
      expect(await outbox.depth(), 0);
      final errs = await db.customSelect('SELECT code FROM sync_errors').get();
      expect(errs.single.read<String>('code'), 'op_id_mutated');
    });

    test('peekBatch respects byte budget', () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final outbox = DriftOutboxStore(db);
      final big = 'x' * 600;
      for (var i = 0; i < 5; i++) {
        await outbox.enqueue(
          Op(
            opId: 'op$i',
            tableName: 'accounts',
            rowId: 'r$i',
            opType: OpType.update,
            fieldsDiff: {'note': big},
            hlc: Hlc(
              wallMillis: 1_500_000_000_000 + i,
              counter: 0,
              nodeId: 'dev',
            ),
            deviceId: 'dev',
          ),
        );
      }
      // Each op encodes roughly ~750 bytes; cap at 1500 should fit ~1-2.
      final batch = await outbox.peekBatch(maxBytes: 1500, maxOps: 100);
      expect(batch.length, lessThanOrEqualTo(2));
      expect(batch.length, greaterThanOrEqualTo(1));
    });

    test('round-trips fields_diff null vs map', () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final outbox = DriftOutboxStore(db);
      await outbox.enqueue(
        makeOp(id: 'del', wall: 1_500_000_000_000, type: OpType.delete),
      );
      await outbox.enqueue(makeOp(id: 'upd', wall: 1_500_000_000_001));
      final batch = await outbox.peekBatch();
      final del = batch.firstWhere((o) => o.opId == 'del');
      final upd = batch.firstWhere((o) => o.opId == 'upd');
      expect(del.opType, OpType.delete);
      expect(del.fieldsDiff, isNull);
      expect(upd.fieldsDiff, isNotNull);
      expect(upd.fieldsDiff!['name'], 'n-upd');
    });
  });

  group('DriftCursorStore', () {
    test('cursor and local hlc round-trip', () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final cursors = DriftCursorStore(db);
      expect(await cursors.readCursor(), isNull);
      const hlc = Hlc(wallMillis: 1_500_000_000_000, counter: 7, nodeId: 'dev');
      await cursors.writeCursor(hlc);
      expect(await cursors.readCursor(), hlc);
      await cursors.writeLocalHlc(hlc);
      expect(await cursors.readLocalHlc(), hlc);
    });

    test('writeCursor is upsert (idempotent)', () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final cursors = DriftCursorStore(db);
      const a = Hlc(wallMillis: 1, counter: 0, nodeId: 'dev');
      const b = Hlc(wallMillis: 2, counter: 0, nodeId: 'dev');
      await cursors.writeCursor(a);
      await cursors.writeCursor(b);
      expect(await cursors.readCursor(), b);
    });
  });
}
