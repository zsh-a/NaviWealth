import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/data/db/app_database.dart';
import 'package:naviwealth/data/domain/enums.dart';
import 'package:naviwealth/data/domain/hlc.dart';

import '../../data/db/test_database.dart';

Future<void> _insertAccount(AppDatabase db, String id, {String? name}) {
  return db
      .into(db.accounts)
      .insert(
        AccountsCompanion.insert(
          id: id,
          type: AccountCategory.cash,
          name: name ?? 'Account $id',
          currency: 'CNY',
          category: const Value(AccountSide.asset),
          ownerUserId: 'user-1',
          updatedAt: DateTime.utc(2026, 1, 1),
          updatedByDevice: 'dev',
          hlc: const Hlc(wallMillis: 1, counter: 0, nodeId: 'dev'),
        ),
      );
}

void main() {
  group('DriftOutboxStore', () {
    test('each enqueue appends a dirty pointer', () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final outbox = DriftOutboxStore(db);
      await outbox.enqueue(table: 'accounts', rowId: 'A-1');
      await outbox.enqueue(table: 'accounts', rowId: 'A-1');
      // The v2 outbox is an append-only log; dedup happens downstream when
      // the engine collapses pointers to one push per row.
      expect(await outbox.depth(), 2);
    });

    test('depth reflects the number of queued pointers', () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final outbox = DriftOutboxStore(db);
      expect(await outbox.depth(), 0);
      await outbox.enqueue(table: 'accounts', rowId: 'A-1');
      await outbox.enqueue(table: 'accounts', rowId: 'A-2');
      expect(await outbox.depth(), 2);
    });
  });

  group('DriftPendingRows', () {
    test('depth matches the op_outbox row count', () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final outbox = DriftOutboxStore(db);
      final pending = DriftPendingRows(db);
      await outbox.enqueue(table: 'accounts', rowId: 'A-1');
      await outbox.enqueue(table: 'accounts', rowId: 'A-2');
      expect(await pending.depth(), 2);
    });

    test('pointers are returned oldest-first', () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final outbox = DriftOutboxStore(db);
      final pending = DriftPendingRows(db);
      await outbox.enqueue(table: 'accounts', rowId: 'A-1');
      await outbox.enqueue(table: 'accounts', rowId: 'A-2');

      final pointers = await pending.pointers();
      expect(pointers.first.table, 'accounts');
      expect(pointers.first.rowId, 'A-1');
      expect(pointers.last.rowId, 'A-2');
    });

    test('readRow snapshots the current row state', () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final pending = DriftPendingRows(db);
      await _insertAccount(db, 'acc-1', name: 'Brokerage');

      final row = await pending.readRow('accounts', 'acc-1');
      expect(row, isNotNull);
      expect(row!['id'], 'acc-1');
      expect(row['name'], 'Brokerage');
      expect(row['currency'], 'CNY');
      expect(row['owner_user_id'], 'user-1');
    });

    test('readRow returns null for a missing row', () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final pending = DriftPendingRows(db);
      expect(await pending.readRow('accounts', 'nope'), isNull);
    });

    test('clear deletes the named op pointers', () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final outbox = DriftOutboxStore(db);
      final pending = DriftPendingRows(db);
      await outbox.enqueue(table: 'accounts', rowId: 'A-1');
      await outbox.enqueue(table: 'accounts', rowId: 'A-2');

      final before = await pending.pointers();
      await pending.clear([before.first.opId]);

      final pointers = await pending.pointers();
      expect(pointers.single.opId, before.last.opId);
      expect(pointers.single.rowId, 'A-2');
      expect(await pending.depth(), 1);
    });

    test('clear with an empty iterable is a no-op', () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final outbox = DriftOutboxStore(db);
      final pending = DriftPendingRows(db);
      await outbox.enqueue(table: 'accounts', rowId: 'A-1');
      await pending.clear(const <String>[]);
      expect(await pending.depth(), 1);
    });
  });

  group('DriftCursorStore', () {
    test('seq round-trips and defaults to 0', () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final cursors = DriftCursorStore(db);
      expect(await cursors.readSeq(), 0);
      await cursors.writeSeq(1342);
      expect(await cursors.readSeq(), 1342);
    });

    test('writeSeq is an idempotent upsert', () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final cursors = DriftCursorStore(db);
      await cursors.writeSeq(10);
      await cursors.writeSeq(20);
      expect(await cursors.readSeq(), 20);
    });

    test('localHlc round-trips and defaults to null', () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final cursors = DriftCursorStore(db);
      expect(await cursors.readLocalHlc(), isNull);
      const hlc = Hlc(wallMillis: 1_500_000_000_000, counter: 7, nodeId: 'dev');
      await cursors.writeLocalHlc(hlc);
      expect(await cursors.readLocalHlc(), hlc);
    });
  });
}
