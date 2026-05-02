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

  group('FIR-126 — accountCategory', () {
    test('create defaults the category from the carrier type', () async {
      final bank = await repo.create(
        type: AccountType.bank,
        name: 'Bank',
        currency: 'CNY',
      );
      expect(bank.category, AccountCategory.asset);

      final liability = await repo.create(
        type: AccountType.liability,
        name: 'Mortgage',
        currency: 'CNY',
      );
      expect(liability.category, AccountCategory.liability);

      // The insert op carries the category so peers learn the new
      // accounting classification on their next pull.
      final batch = await outbox.peekBatch();
      expect(batch, hasLength(2));
      expect(batch.first.fieldsDiff!['category'], 'asset');
      expect(batch.last.fieldsDiff!['category'], 'liability');
    });

    test('create honours an explicit category override', () async {
      final acc = await repo.create(
        type: AccountType.other,
        name: '工资',
        currency: 'CNY',
        category: AccountCategory.income,
      );
      expect(acc.category, AccountCategory.income);
    });

    test('update with a new category emits a single-field diff', () async {
      final acc = await repo.create(
        type: AccountType.other,
        name: 'TBD',
        currency: 'CNY',
      );
      await outbox.ack((await outbox.peekBatch()).map((o) => o.opId).toList());

      final updated = await repo.update(
        acc.id,
        category: AccountCategory.equity,
      );
      expect(updated.category, AccountCategory.equity);

      final batch = await outbox.peekBatch();
      expect(batch, hasLength(1));
      final diff = batch.single.fieldsDiff!;
      expect(diff['category'], 'equity');
      expect(diff.containsKey('name'), isFalse);
      expect(diff.containsKey('type'), isFalse);
    });

    test('seedSystemAccounts inserts income / expense / equity once', () async {
      final inserted = await repo.seedSystemAccounts();
      expect(inserted, 3);

      // Re-running is a free no-op — same primary keys, no duplicates.
      final reseeded = await repo.seedSystemAccounts();
      expect(reseeded, 0);

      final ops = await outbox.peekBatch();
      // Three inserts on the first call only; the no-op doesn't queue.
      expect(ops, hasLength(3));
      expect(ops.map((o) => o.fieldsDiff!['category']).toSet(), {
        'income',
        'expense',
        'equity',
      });
    });

    test(
      'seedSystemAccounts uses deterministic ids per (user, category)',
      () async {
        await repo.seedSystemAccounts();
        final id = AccountRepository.systemAccountIdFor(
          AccountCategory.income,
          ownerUserId: 'u-test',
        );
        final row = await repo.findById(id);
        expect(row, isNotNull);
        expect(row!.category, AccountCategory.income);
      },
    );

    test(
      'listActive hides system accounts but keeps user accounts visible',
      () async {
        await repo.seedSystemAccounts();
        final user = await repo.create(
          type: AccountType.bank,
          name: '招行储蓄',
          currency: 'CNY',
        );

        final active = await repo.listActive();
        expect(active.map((a) => a.id), [user.id]);
      },
    );
  });
}
