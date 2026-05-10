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
      type: AccountCategory.bank,
      name: '招行储蓄',
      currency: 'CNY',
      institution: '招商银行',
    );

    expect(account.name, '招行储蓄');
    expect(account.type, AccountCategory.bank);
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
      type: AccountCategory.broker,
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
      type: AccountCategory.cash,
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
      type: AccountCategory.bank,
      name: 'Live',
      currency: 'USD',
    );
    final archived = await repo.create(
      type: AccountCategory.broker,
      name: 'Archived',
      currency: 'USD',
    );
    final deleted = await repo.create(
      type: AccountCategory.cash,
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
      type: AccountCategory.bank,
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
        type: AccountCategory.bank,
        name: 'Bank',
        currency: 'CNY',
      );
      expect(bank.category, AccountSide.asset);

      final liability = await repo.create(
        type: AccountCategory.liability,
        name: 'Mortgage',
        currency: 'CNY',
      );
      expect(liability.category, AccountSide.liability);

      // The insert op carries the category so peers learn the new
      // accounting classification on their next pull.
      final batch = await outbox.peekBatch();
      expect(batch, hasLength(2));
      expect(batch.first.fieldsDiff!['category'], 'asset');
      expect(batch.last.fieldsDiff!['category'], 'liability');
    });

    test('create honours an explicit category override', () async {
      final acc = await repo.create(
        type: AccountCategory.asset,
        name: '工资',
        currency: 'CNY',
        category: AccountSide.income,
      );
      expect(acc.category, AccountSide.income);
    });

    test('update with a new category emits a single-field diff', () async {
      final acc = await repo.create(
        type: AccountCategory.asset,
        name: 'TBD',
        currency: 'CNY',
      );
      await outbox.ack((await outbox.peekBatch()).map((o) => o.opId).toList());

      final updated = await repo.update(
        acc.id,
        category: AccountSide.equity,
      );
      expect(updated.category, AccountSide.equity);

      final batch = await outbox.peekBatch();
      expect(batch, hasLength(1));
      final diff = batch.single.fieldsDiff!;
      expect(diff['category'], 'equity');
      expect(diff.containsKey('name'), isFalse);
      expect(diff.containsKey('type'), isFalse);
    });

    test('seedSystemAccounts inserts the full tree once', () async {
      final inserted = await repo.seedSystemAccounts();
      // 3 roots (income / expense / equity) + expense subtree leaves.
      // 27 total today — the count is asserted concretely so a future
      // seed change has to update the contract.
      expect(inserted, 27);

      // Re-running is a free no-op — same primary keys, no duplicates.
      final reseeded = await repo.seedSystemAccounts();
      expect(reseeded, 0);

      final ops = await outbox.peekBatch();
      // Inserts on the first call only; the no-op doesn't queue.
      expect(ops, hasLength(27));
      // The tree's three top-level buckets are present.
      final categories = ops.map((o) => o.fieldsDiff!['category']).toSet();
      expect(categories, {'income', 'expense', 'equity'});
    });

    test(
      'seedSystemAccounts uses deterministic ids per (user, category)',
      () async {
        await repo.seedSystemAccounts();
        final id = AccountRepository.systemAccountIdFor(
          AccountSide.income,
          ownerUserId: 'u-test',
        );
        final row = await repo.findById(id);
        expect(row, isNotNull);
        expect(row!.category, AccountSide.income);
      },
    );

    test(
      'listActive hides system accounts but keeps user accounts visible',
      () async {
        await repo.seedSystemAccounts();
        final user = await repo.create(
          type: AccountCategory.bank,
          name: '招行储蓄',
          currency: 'CNY',
        );

        final active = await repo.listActive();
        expect(active.map((a) => a.id), [user.id]);
      },
    );
  });

  group('FIR-133 — account tree', () {
    test('create round-trips parentId / icon / color', () async {
      final parent = await repo.create(
        type: AccountCategory.asset,
        name: 'Bills',
        currency: 'CNY',
        category: AccountSide.expense,
        icon: 'receipt_long',
        color: '#EF4444',
      );
      expect(parent.parentId, isNull);
      expect(parent.icon, 'receipt_long');
      expect(parent.color, '#EF4444');

      final child = await repo.create(
        type: AccountCategory.asset,
        name: 'Electricity',
        currency: 'CNY',
        category: AccountSide.expense,
        parentId: parent.id,
        icon: 'bolt',
        color: '#F97316',
      );
      expect(child.parentId, parent.id);
      expect(child.icon, 'bolt');
      expect(child.color, '#F97316');

      final ops = await outbox.peekBatch();
      // Both rows carry the new columns in their insert op so peers
      // reconstruct the tree on the next pull.
      expect(ops.last.fieldsDiff!['parent_id'], parent.id);
      expect(ops.last.fieldsDiff!['icon'], 'bolt');
      expect(ops.last.fieldsDiff!['color'], '#F97316');
    });

    test('update emits per-field diffs for parentId / icon / color', () async {
      final acc = await repo.create(
        type: AccountCategory.asset,
        name: 'Misc',
        currency: 'CNY',
        category: AccountSide.expense,
      );
      await outbox.ack((await outbox.peekBatch()).map((o) => o.opId).toList());

      // Re-parent + recolor in a single update.
      final updated = await repo.update(
        acc.id,
        parentId: 'system-account:u-test:expense',
        icon: 'shopping_cart',
        color: '#10B981',
      );
      expect(updated.parentId, 'system-account:u-test:expense');
      expect(updated.icon, 'shopping_cart');
      expect(updated.color, '#10B981');

      final batch = await outbox.peekBatch();
      final diff = batch.single.fieldsDiff!;
      expect(diff['parent_id'], 'system-account:u-test:expense');
      expect(diff['icon'], 'shopping_cart');
      expect(diff['color'], '#10B981');
      // Untouched columns stay out of the diff (LWW field-level).
      expect(diff.containsKey('name'), isFalse);
      expect(diff.containsKey('category'), isFalse);
    });

    test('clearParentId nulls the link in the diff', () async {
      final root = await repo.create(
        type: AccountCategory.asset,
        name: 'Top',
        currency: 'CNY',
        category: AccountSide.expense,
      );
      final child = await repo.create(
        type: AccountCategory.asset,
        name: 'Leaf',
        currency: 'CNY',
        category: AccountSide.expense,
        parentId: root.id,
      );
      await outbox.ack((await outbox.peekBatch()).map((o) => o.opId).toList());

      await repo.update(child.id, clearParentId: true);
      final reloaded = await repo.findById(child.id);
      expect(reloaded!.parentId, isNull);

      final diff = (await outbox.peekBatch()).single.fieldsDiff!;
      expect(diff.containsKey('parent_id'), isTrue);
      expect(diff['parent_id'], isNull);
    });

    test('seedSystemAccounts wires parent_id and icon/color', () async {
      await repo.seedSystemAccounts();

      final salary = await repo.findById(
        AccountRepository.systemAccountIdForPath(
          'income:salary',
          ownerUserId: 'u-test',
        ),
      );
      expect(salary, isNotNull);
      expect(salary!.parentId, 'system-account:u-test:income');
      expect(salary.category, AccountSide.income);
      expect(salary.icon, 'work');
      expect(salary.color, '#10B981');

      // Trading branch sits one level deeper than the rest.
      final tradingFee = await repo.findById(
        AccountRepository.systemAccountIdForPath(
          'expense:trading:fee',
          ownerUserId: 'u-test',
        ),
      );
      expect(tradingFee, isNotNull);
      expect(tradingFee!.parentId, 'system-account:u-test:expense:trading');
    });

    test('accountsByParent returns top-level when parent is null', () async {
      await repo.seedSystemAccounts();
      final roots = await repo.accountsByParent(null);
      // Three roots — Income / Expenses / Equity.
      expect(
        roots.map((a) => a.id).toSet(),
        {
          'system-account:u-test:income',
          'system-account:u-test:expense',
          'system-account:u-test:equity',
        },
      );
    });

    test('accountsByParent lists direct children only', () async {
      await repo.seedSystemAccounts();
      final incomeChildren = await repo.accountsByParent(
        'system-account:u-test:income',
      );
      expect(
        incomeChildren.map((a) => a.id),
        containsAll([
          'system-account:u-test:income:salary',
          'system-account:u-test:income:dividend',
          'system-account:u-test:income:interest',
          'system-account:u-test:income:capitalGains',
          'system-account:u-test:income:other',
        ]),
      );
      // Trading:Fee is a grand-child of Expenses, not Income.
      expect(
        incomeChildren.map((a) => a.id),
        isNot(contains('system-account:u-test:expense:trading:fee')),
      );
    });

    test('walkSubtree returns root then all descendants', () async {
      await repo.seedSystemAccounts();
      final subtree = await repo.walkSubtree(
        'system-account:u-test:expense',
      );
      // Expenses subtree: 1 root + 12 direct children (one per
      // expense slug) + 1 trading branch + 3 trading grand-children
      // = 17 nodes.
      expect(subtree, hasLength(17));
      expect(subtree.first.id, 'system-account:u-test:expense');
      expect(
        subtree.map((a) => a.id),
        containsAll([
          'system-account:u-test:expense:trading',
          'system-account:u-test:expense:trading:fee',
          'system-account:u-test:expense:trading:tax',
          'system-account:u-test:expense:trading:interest',
          'system-account:u-test:expense:transport',
          'system-account:u-test:expense:education',
          'system-account:u-test:expense:gift',
        ]),
      );
    });

    test('walkSubtree returns empty list for a deleted root', () async {
      await repo.seedSystemAccounts();
      await repo.softDelete('system-account:u-test:expense');
      final subtree = await repo.walkSubtree(
        'system-account:u-test:expense',
      );
      expect(subtree, isEmpty);
    });

    test('pathOf returns the chain from root to leaf', () async {
      await repo.seedSystemAccounts();
      final path = await repo.pathOf(
        'system-account:u-test:expense:trading:fee',
      );
      expect(
        path.map((a) => a.id),
        [
          'system-account:u-test:expense',
          'system-account:u-test:expense:trading',
          'system-account:u-test:expense:trading:fee',
        ],
      );
    });

    test('pathOf returns empty list for an unknown account', () async {
      final path = await repo.pathOf('no-such-account');
      expect(path, isEmpty);
    });
  });
}
