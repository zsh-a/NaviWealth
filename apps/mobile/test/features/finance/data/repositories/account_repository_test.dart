import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/core/sync/op_outbox.dart';
import 'package:naviwealth/features/finance/data/repositories/account_mutation_receipt.dart';
import 'package:naviwealth/features/finance/data/repositories/account_repository.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/expense/domain/expense_category_taxonomy.dart';

import '../../../../core/persistence/test_database.dart';
import '../../../../core/sync/_outbox_test_ext.dart';
import '_stub_stamper.dart';

class _FailingOutbox implements OutboxStore {
  int calls = 0;

  @override
  Future<int> depth() async => 0;

  @override
  Future<void> enqueue({required String table, required String rowId}) async {
    calls += 1;
    throw StateError('outbox unavailable');
  }
}

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

  test('create writes the row and queues a dirty pointer', () async {
    final account = await repo.create(
      type: AccountCategory.bank,
      name: '招行储蓄',
      currency: 'CNY',
      institution: '招商银行',
    );

    expect(account.name, '招行储蓄');
    expect(account.type, AccountCategory.bank);
    expect(account.sync.ownerUserId, 'u-test');

    final batch = outbox.queued;
    expect(batch, hasLength(1));
    final op = batch.single;
    expect(op.table, 'accounts');
    expect(op.rowId, account.id);
  });

  test('update queues a dirty pointer and bumps HLC', () async {
    final account = await repo.create(
      type: AccountCategory.broker,
      name: 'Original',
      currency: 'USD',
    );
    outbox.clearQueued();

    final updated = await repo.update(account.id, name: 'Renamed');
    expect(updated.name, 'Renamed');
    expect(updated.sync.hlc, isNot(account.sync.hlc));

    final batch = outbox.queued;
    expect(batch, hasLength(1));
    final op = batch.single;
    expect(op.table, 'accounts');
    expect(op.rowId, account.id);
  });

  test('softDelete writes a tombstone and queues a dirty pointer', () async {
    final account = await repo.create(
      type: AccountCategory.cash,
      name: '现金',
      currency: 'CNY',
    );
    outbox.clearQueued();

    await repo.softDelete(account.id);
    final reloaded = await repo.findById(account.id);
    expect(reloaded!.sync.deletedAt, isNotNull);

    final batch = outbox.queued;
    expect(batch, hasLength(1));
    expect(batch.single.table, 'accounts');
    expect(batch.single.rowId, account.id);
  });

  group('manual account mutation receipts', () {
    test(
      'full editable save round-trips every field and Undo restores before',
      () async {
        final created = await repo.saveEditable(
          type: AccountCategory.bank,
          name: 'Before',
          currency: 'CNY',
          category: AccountSide.asset,
          archived: false,
          institution: 'Bank',
          accountNumber: '1234',
          note: 'Before note',
          parentId: 'parent-before',
          icon: 'wallet',
          color: '#111111',
        );
        final edit = await repo.saveEditable(
          id: created.after.id,
          type: AccountCategory.liability,
          name: 'After',
          currency: 'USD',
          category: AccountSide.liability,
          archived: true,
          institution: null,
          accountNumber: null,
          note: null,
          parentId: null,
          icon: null,
          color: null,
        );

        expect(edit.before, created.after);
        expect(edit.after.type, AccountCategory.liability);
        expect(edit.after.category, AccountSide.liability);
        expect(edit.after.archived, isTrue);
        expect(edit.after.institution, isNull);
        expect(edit.after.accountNumber, isNull);
        expect(edit.after.note, isNull);
        expect(edit.after.parentId, isNull);
        expect(edit.after.icon, isNull);
        expect(edit.after.color, isNull);

        await repo.undoMutation(edit);
        final restored = await repo.findById(created.after.id);
        expect(restored!.type, AccountCategory.bank);
        expect(restored.category, AccountSide.asset);
        expect(restored.archived, isFalse);
        expect(restored.institution, 'Bank');
        expect(restored.accountNumber, '1234');
        expect(restored.note, 'Before note');
        expect(restored.parentId, 'parent-before');
        expect(restored.icon, 'wallet');
        expect(restored.color, '#111111');
      },
    );

    test('Undo create tombstones the exact committed version', () async {
      final receipt = await repo.saveEditable(
        type: AccountCategory.cash,
        name: 'Temporary',
        currency: 'CNY',
        category: AccountSide.asset,
        archived: false,
        institution: null,
        accountNumber: null,
        note: null,
        parentId: null,
        icon: null,
        color: null,
      );
      outbox.clearQueued();

      await repo.undoMutation(receipt);

      expect(
        (await repo.findById(receipt.after.id))!.sync.deletedAt,
        isNotNull,
      );
      expect(outbox.queued, hasLength(1));
      expect(outbox.queued.single.rowId, receipt.after.id);
    });

    test(
      'later account version rejects Undo without writes or outbox',
      () async {
        final created = await repo.saveEditable(
          type: AccountCategory.bank,
          name: 'Before',
          currency: 'CNY',
          category: AccountSide.asset,
          archived: false,
          institution: null,
          accountNumber: null,
          note: null,
          parentId: null,
          icon: null,
          color: null,
        );
        final edit = await repo.saveEditable(
          id: created.after.id,
          type: AccountCategory.bank,
          name: 'Committed',
          currency: 'CNY',
          category: AccountSide.asset,
          archived: false,
          institution: null,
          accountNumber: null,
          note: null,
          parentId: null,
          icon: null,
          color: null,
        );
        await repo.update(created.after.id, name: 'Later edit');
        outbox.clearQueued();

        await expectLater(
          repo.undoMutation(edit),
          throwsA(isA<AccountMutationConflict>()),
        );

        expect((await repo.findById(created.after.id))!.name, 'Later edit');
        expect(outbox.queued, isEmpty);
      },
    );

    test('outbox failure rolls the conditional Undo back atomically', () async {
      final receipt = await repo.saveEditable(
        type: AccountCategory.bank,
        name: 'Committed',
        currency: 'CNY',
        category: AccountSide.asset,
        archived: false,
        institution: null,
        accountNumber: null,
        note: null,
        parentId: null,
        icon: null,
        color: null,
      );
      final failingOutbox = _FailingOutbox();
      final failingRepo = AccountRepository(
        db: db,
        outbox: failingOutbox,
        stamper: makeStubStamper(initialMillis: 1_800_000_000_000),
      );

      await expectLater(
        failingRepo.undoMutation(receipt),
        throwsA(isA<StateError>()),
      );

      expect(await repo.findById(receipt.after.id), receipt.after);
      expect(failingOutbox.calls, 1);
    });
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

  test(
    'clearInstitution nulls the column and queues a dirty pointer',
    () async {
      final acc = await repo.create(
        type: AccountCategory.bank,
        name: 'A',
        currency: 'CNY',
        institution: '招商银行',
      );
      outbox.clearQueued();

      await repo.update(acc.id, clearInstitution: true);
      final reloaded = await repo.findById(acc.id);
      expect(reloaded!.institution, isNull);

      final batch = outbox.queued;
      expect(batch, hasLength(1));
      expect(batch.single.table, 'accounts');
      expect(batch.single.rowId, acc.id);
    },
  );

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

      // Each create queues one dirty pointer; the sync engine reads the
      // row's current state (including its category) at push time.
      final batch = outbox.queued;
      expect(batch, hasLength(2));
      expect(batch.first.rowId, bank.id);
      expect(batch.last.rowId, liability.id);
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

    test('update with a new category queues a dirty pointer', () async {
      final acc = await repo.create(
        type: AccountCategory.asset,
        name: 'TBD',
        currency: 'CNY',
      );
      outbox.clearQueued();

      final updated = await repo.update(acc.id, category: AccountSide.equity);
      expect(updated.category, AccountSide.equity);

      final batch = outbox.queued;
      expect(batch, hasLength(1));
      expect(batch.single.table, 'accounts');
      expect(batch.single.rowId, acc.id);
    });

    test('seedSystemAccounts inserts the full tree once', () async {
      final inserted = await repo.seedSystemAccounts();
      // 3 roots plus seeded income / expense / equity leaves.
      // 38 total today — the count is asserted concretely so a future
      // seed change has to update the contract.
      expect(inserted, 38);

      // Re-running is a free no-op — same primary keys, no duplicates.
      final reseeded = await repo.seedSystemAccounts();
      expect(reseeded, 0);

      final ops = outbox.queued;
      // Inserts on the first call only; the no-op doesn't queue.
      expect(ops, hasLength(38));
      expect(ops.every((o) => o.table == 'accounts'), isTrue);
    });

    test('seedSystemAccounts does not stamp when rows already exist', () async {
      var stampCount = 0;
      var millis = 1_700_000_000_000;
      final countingRepo = AccountRepository(
        db: db,
        outbox: outbox,
        stamper: MutationStamper(
          currentUserId: () async => 'u-test',
          deviceId: () async => 'dev-test',
          stampHlc: () async {
            stampCount++;
            return Hlc(wallMillis: millis++, counter: 0, nodeId: 'dev-test');
          },
        ),
      );

      expect(await countingRepo.seedSystemAccounts(), 38);
      expect(stampCount, 38);

      expect(await countingRepo.seedSystemAccounts(), 0);
      expect(stampCount, 38);
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

      final ops = outbox.queued;
      // Both rows queue a dirty pointer; the engine reads each row's full
      // current state (parent_id / icon / color) at push time.
      expect(ops, hasLength(2));
      expect(ops.last.rowId, child.id);
    });

    test('update queues a dirty pointer for parentId / icon / color', () async {
      final acc = await repo.create(
        type: AccountCategory.asset,
        name: 'Misc',
        currency: 'CNY',
        category: AccountSide.expense,
      );
      outbox.clearQueued();

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

      final batch = outbox.queued;
      expect(batch, hasLength(1));
      expect(batch.single.table, 'accounts');
      expect(batch.single.rowId, acc.id);
    });

    test('clearParentId nulls the link and queues a dirty pointer', () async {
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
      outbox.clearQueued();

      await repo.update(child.id, clearParentId: true);
      final reloaded = await repo.findById(child.id);
      expect(reloaded!.parentId, isNull);

      final batch = outbox.queued;
      expect(batch, hasLength(1));
      expect(batch.single.table, 'accounts');
      expect(batch.single.rowId, child.id);
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
      expect(roots.map((a) => a.id).toSet(), {
        'system-account:u-test:income',
        'system-account:u-test:expense',
        'system-account:u-test:equity',
      });
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
      final subtree = await repo.walkSubtree('system-account:u-test:expense');
      // Expenses subtree: 1 root + 22 direct children (everyday leaves plus
      // trading/tax branches) + 3 trading grand-children + 1 tax grand-child.
      expect(subtree, hasLength(27));
      expect(subtree.first.id, 'system-account:u-test:expense');
      expect(
        subtree.map((a) => a.id),
        containsAll([
          'system-account:u-test:expense:dining',
          'system-account:u-test:expense:groceries',
          'system-account:u-test:expense:coffee',
          'system-account:u-test:expense:trading',
          'system-account:u-test:expense:trading:fee',
          'system-account:u-test:expense:trading:tax',
          'system-account:u-test:expense:trading:interest',
          'system-account:u-test:expense:tax',
          'system-account:u-test:expense:tax:withholding',
          'system-account:u-test:expense:transport',
          'system-account:u-test:expense:utilities',
          'system-account:u-test:expense:subscriptions',
          'system-account:u-test:expense:education',
          'system-account:u-test:expense:fitness',
          'system-account:u-test:expense:gift',
          'system-account:u-test:expense:pets',
        ]),
      );
    });

    test('seeded expense accounts cover the canonical taxonomy', () async {
      await repo.seedSystemAccounts();

      for (final category in kExpenseCategoryTaxonomy) {
        final account = await repo.findById(
          AccountRepository.systemAccountIdForPath(
            category.accountPath,
            ownerUserId: 'u-test',
          ),
        );
        expect(account, isNotNull, reason: category.slug);
        expect(account!.category, AccountSide.expense, reason: category.slug);
      }
    });

    test('walkSubtree returns empty list for a deleted root', () async {
      await repo.seedSystemAccounts();
      await repo.softDelete('system-account:u-test:expense');
      final subtree = await repo.walkSubtree('system-account:u-test:expense');
      expect(subtree, isEmpty);
    });

    test('pathOf returns the chain from root to leaf', () async {
      await repo.seedSystemAccounts();
      final path = await repo.pathOf(
        'system-account:u-test:expense:trading:fee',
      );
      expect(path.map((a) => a.id), [
        'system-account:u-test:expense',
        'system-account:u-test:expense:trading',
        'system-account:u-test:expense:trading:fee',
      ]);
    });

    test('pathOf returns empty list for an unknown account', () async {
      final path = await repo.pathOf('no-such-account');
      expect(path, isEmpty);
    });
  });
}
