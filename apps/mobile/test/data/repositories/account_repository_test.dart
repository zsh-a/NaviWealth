import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/op.dart';
import 'package:naviwealth/data/db/app_database.dart';
import 'package:naviwealth/data/domain/enums.dart';
import 'package:naviwealth/data/repositories/account_repository.dart';

import '../db/test_database.dart';
import '_stub_stamper.dart';

void main() {
  late AppDatabase db;
  late InMemoryOutboxStore outbox;
  late AccountRepository repo;

  setUp(() {
    db = makeTestDatabase();
    outbox = InMemoryOutboxStore();
    repo = AccountRepository(
      db: db,
      outbox: outbox,
      stamper: makeStubStamper(),
    );
  });

  tearDown(() async {
    await db.close();
  });

  test('create writes the row and queues an insert op', () async {
    final account = await repo.create(
      type: AccountType.bank,
      name: '招行储蓄',
      currency: 'CNY',
      institution: '招商银行',
    );

    expect(account.name, '招行储蓄');
    expect(account.type, AccountType.bank);
    expect(account.sync.ownerUserId, 'u-test');

    final batch = await outbox.peekBatch();
    expect(batch, hasLength(1));
    final op = batch.single;
    expect(op.tableName, 'accounts');
    expect(op.opType, OpType.insert);
    expect(op.rowId, account.id);
    expect(op.fieldsDiff!['name'], '招行储蓄');
    expect(op.fieldsDiff!['type'], 'bank');
  });

  test('update only diffs the changed fields and bumps HLC', () async {
    final account = await repo.create(
      type: AccountType.brokerage,
      name: 'Original',
      currency: 'USD',
    );
    await outbox.ack((await outbox.peekBatch()).map((o) => o.opId).toList());

    final updated = await repo.update(account.id, name: 'Renamed');
    expect(updated.name, 'Renamed');
    expect(updated.sync.hlc, isNot(account.sync.hlc));

    final batch = await outbox.peekBatch();
    expect(batch, hasLength(1));
    final op = batch.single;
    expect(op.opType, OpType.update);
    expect(op.fieldsDiff!.containsKey('name'), isTrue);
    expect(op.fieldsDiff!['name'], 'Renamed');
    // Type wasn't part of the patch, so it must NOT appear in the diff.
    expect(op.fieldsDiff!.containsKey('type'), isFalse);
  });

  test('softDelete writes a tombstone and queues a delete op', () async {
    final account = await repo.create(
      type: AccountType.cash,
      name: '现金',
      currency: 'CNY',
    );
    await outbox.ack((await outbox.peekBatch()).map((o) => o.opId).toList());

    await repo.softDelete(account.id);
    final reloaded = await repo.findById(account.id);
    expect(reloaded!.sync.deletedAt, isNotNull);

    final batch = await outbox.peekBatch();
    expect(batch, hasLength(1));
    expect(batch.single.opType, OpType.delete);
    expect(batch.single.fieldsDiff, isNull);
  });

  test('listActive excludes archived and deleted accounts', () async {
    final live = await repo.create(
      type: AccountType.bank,
      name: 'Live',
      currency: 'USD',
    );
    final archived = await repo.create(
      type: AccountType.brokerage,
      name: 'Archived',
      currency: 'USD',
    );
    final deleted = await repo.create(
      type: AccountType.cash,
      name: 'Deleted',
      currency: 'CNY',
    );
    await repo.update(archived.id, archived: true);
    await repo.softDelete(deleted.id);

    final active = await repo.listActive();
    expect(active.map((a) => a.id), [live.id]);
  });

  test('clearInstitution serialises a null in the diff', () async {
    final acc = await repo.create(
      type: AccountType.bank,
      name: 'A',
      currency: 'CNY',
      institution: '招商银行',
    );
    await outbox.ack((await outbox.peekBatch()).map((o) => o.opId).toList());

    await repo.update(acc.id, clearInstitution: true);
    final reloaded = await repo.findById(acc.id);
    expect(reloaded!.institution, isNull);

    final batch = await outbox.peekBatch();
    final diff = batch.single.fieldsDiff!;
    expect(diff.containsKey('institution'), isTrue);
    expect(diff['institution'], isNull);
  });
}
