import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_repository.dart';
import 'package:naviwealth/features/finance/domain/models/entry_kind.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/domain/models/invariants.dart';
import 'package:naviwealth/features/finance/domain/models/posting.dart';

import '../../../../core/persistence/test_database.dart';
import '../../../../core/sync/_outbox_test_ext.dart';
import '_stub_stamper.dart';

class _IdentityFx implements FxRateSource {
  const _IdentityFx();
  @override
  Decimal? rate({
    required String from,
    required String to,
    required DateTime asOf,
  }) => from == to ? Decimal.one : Decimal.one;
}

void main() {
  late AppDatabase db;
  late InMemoryOutboxStore outbox;
  late JournalEntryRepository repo;

  setUp(() {
    db = makeTestDatabase();
    outbox = InMemoryOutboxStore();
    repo = JournalEntryRepository(
      db: db,
      outbox: outbox,
      stamper: makeStubStamper(),
      fxRateSource: const _IdentityFx(),
      baseCurrency: 'USD',
    );
  });

  tearDown(() async {
    await db.close();
  });

  PostingDraft cashLeg(String accountId, String units) => PostingDraft(
    accountId: accountId,
    units: Decimal.parse(units),
    unit: 'USD',
  );

  test('create writes JE + postings and queues one op per row', () async {
    final je = await repo.create(
      entry: JournalEntryDraft(
        date: DateTime.utc(2026, 1, 15),
        narration: 'Transfer',
      ),
      postings: [
        cashLeg('acct:bank:a', '-100.00'),
        cashLeg('acct:bank:b', '100.00'),
      ],
    );
    expect(je.entry.narration, 'Transfer');
    expect(je.postings, hasLength(2));
    expect(je.postings[0].position, 0);
    expect(je.postings[1].position, 1);

    final batch = outbox.queued;
    // 1 JE pointer + 2 posting pointers.
    expect(batch, hasLength(3));
    expect(batch.map((o) => o.table).toSet(), {'journal_entries', 'postings'});
    final je0 = batch.firstWhere((o) => o.table == 'journal_entries');
    expect(je0.rowId, je.entry.id);
  });

  test('create rejects unbalanced postings before touching the DB', () async {
    expect(
      () => repo.create(
        entry: JournalEntryDraft(
          date: DateTime.utc(2026, 1, 15),
          narration: 'Bad',
        ),
        postings: [
          cashLeg('a', '-100.00'),
          cashLeg('b', '50.00'), // Σ = -50 USD.
        ],
      ),
      throwsA(isA<JournalEntryUnbalancedException>()),
    );
    // Nothing was written.
    final entries = await db.select(db.journalEntries).get();
    expect(entries, isEmpty);
    final ops = outbox.queued;
    expect(ops, isEmpty);
  });

  test('getById returns the JE plus postings in position order', () async {
    final je = await repo.create(
      entry: JournalEntryDraft(
        date: DateTime.utc(2026, 1, 15),
        narration: 'Trade',
      ),
      postings: [
        PostingDraft(
          accountId: 'broker:hk',
          units: Decimal.parse('100'),
          unit: 'us_stock:AAPL',
          cost: Cost(perUnit: Decimal.parse('150'), currency: 'USD'),
        ),
        cashLeg('broker:cash', '-15000.00'),
      ],
    );
    final reloaded = await repo.getById(je.entry.id);
    expect(reloaded, isNotNull);
    expect(reloaded!.postings.map((p) => p.position), [0, 1]);
    expect(reloaded.postings.first.cost?.perUnit, Decimal.parse('150'));
    expect(reloaded.postings.first.unit, 'us_stock:AAPL');
  });

  test('balanceByAccountUnit isolates units on mixed-unit accounts', () async {
    await repo.create(
      entry: JournalEntryDraft(
        date: DateTime.utc(2026, 1, 15),
        narration: 'Buy security',
      ),
      postings: [
        PostingDraft(
          accountId: 'broker',
          units: Decimal.parse('10'),
          unit: 'cn_a:600519',
          cost: Cost(perUnit: Decimal.parse('100'), currency: 'USD'),
        ),
        PostingDraft(
          accountId: 'broker',
          units: Decimal.parse('-1000'),
          unit: 'USD',
        ),
      ],
    );

    expect(await repo.balanceByAccount('broker'), Decimal.parse('-990'));
    expect(
      await repo.balanceByAccountUnit('broker', 'USD'),
      Decimal.parse('-1000'),
    );
    expect(
      await repo.balanceByAccountUnit('broker', 'cn_a:600519'),
      Decimal.parse('10'),
    );
  });

  test(
    'softDelete tombstones JE + every posting and queues dirty pointers',
    () async {
      final je = await repo.create(
        entry: JournalEntryDraft(
          date: DateTime.utc(2026, 1, 15),
          narration: 'Tx',
        ),
        postings: [cashLeg('a', '-50.00'), cashLeg('b', '50.00')],
      );
      outbox.clearQueued();

      await repo.softDelete(je.entry.id);

      expect(await repo.getById(je.entry.id), isNull);
      final batch = outbox.queued;
      expect(batch, hasLength(3));
      final tables = batch.map((o) => o.table).toSet();
      expect(tables, {'journal_entries', 'postings'});
    },
  );

  group('watchAllWithPostings', () {
    test('emits an empty list when the ledger has no entries', () async {
      final first = await repo.watchAllWithPostings().first;
      expect(first, isEmpty);
    });

    test(
      'after a create, emits the JE with its posting sub-list grouped',
      () async {
        await repo.create(
          entry: JournalEntryDraft(
            date: DateTime.utc(2026, 1, 15),
            narration: 'Transfer',
          ),
          postings: [
            cashLeg('acct:bank:a', '-100.00'),
            cashLeg('acct:bank:b', '100.00'),
          ],
        );
        final list = await repo.watchAllWithPostings().first;
        expect(list, hasLength(1));
        expect(list.single.entry.narration, 'Transfer');
        expect(list.single.postings, hasLength(2));
        // Postings come back ordered by position.
        expect(list.single.postings[0].position, 0);
        expect(list.single.postings[0].units, Decimal.parse('-100.00'));
        expect(list.single.postings[1].position, 1);
        expect(list.single.postings[1].units, Decimal.parse('100.00'));
      },
    );

    test(
      'orders by `(date DESC, id ASC)` so newest entries surface first',
      () async {
        await repo.create(
          entry: JournalEntryDraft(
            id: 'je-old',
            date: DateTime.utc(2026, 1, 1),
            narration: 'Old',
          ),
          postings: [cashLeg('a', '-1'), cashLeg('b', '1')],
        );
        await repo.create(
          entry: JournalEntryDraft(
            id: 'je-new',
            date: DateTime.utc(2026, 6, 1),
            narration: 'New',
          ),
          postings: [cashLeg('a', '-2'), cashLeg('b', '2')],
        );
        final list = await repo.watchAllWithPostings().first;
        expect(list.map((e) => e.entry.narration), ['New', 'Old']);
      },
    );

    test(
      'soft-deleted JEs and their postings drop out of the stream',
      () async {
        final je = await repo.create(
          entry: JournalEntryDraft(
            date: DateTime.utc(2026, 1, 15),
            narration: 'Doomed',
          ),
          postings: [cashLeg('a', '-1'), cashLeg('b', '1')],
        );
        expect(await repo.watchAllWithPostings().first, hasLength(1));
        await repo.softDelete(je.entry.id);
        expect(await repo.watchAllWithPostings().first, isEmpty);
      },
    );

    test('each emission is independent — the per-JE posting list is a fresh '
        'snapshot, never mutated in place', () async {
      // Defends against an `addAll` regression where two JEs that share
      // a `journal_entry_id` group could accidentally see each other's
      // postings. We seed two JEs with overlapping accounts but
      // distinct posting ids and assert the cross-pollination doesn't
      // happen.
      await repo.create(
        entry: JournalEntryDraft(
          id: 'je-1',
          date: DateTime.utc(2026, 1, 1),
          narration: 'One',
        ),
        postings: [cashLeg('shared', '-1'), cashLeg('a', '1')],
      );
      await repo.create(
        entry: JournalEntryDraft(
          id: 'je-2',
          date: DateTime.utc(2026, 2, 1),
          narration: 'Two',
        ),
        postings: [cashLeg('shared', '-2'), cashLeg('b', '2')],
      );
      final list = await repo.watchAllWithPostings().first;
      expect(list.map((e) => e.entry.id).toSet(), {'je-1', 'je-2'});
      for (final je in list) {
        expect(
          je.postings.every((p) => p.journalEntryId == je.entry.id),
          isTrue,
          reason:
              'cross-pollinated postings for ${je.entry.id}: '
              '${je.postings.map((p) => p.journalEntryId).toList()}',
        );
      }
    });
  });

  group('watchExpenses', () {
    test('projects the paying account from sibling postings', () async {
      await _insertAccount(
        db,
        id: 'cash',
        side: AccountSide.asset,
        type: AccountCategory.cash,
      );
      await _insertAccount(
        db,
        id: 'food',
        side: AccountSide.expense,
        type: AccountCategory.asset,
      );
      await repo.create(
        entry: JournalEntryDraft(
          id: 'je-expense',
          date: DateTime.utc(2026, 5, 1),
          narration: 'Lunch',
        ),
        postings: [cashLeg('food', '12.50'), cashLeg('cash', '-12.50')],
      );

      final expenses = await repo.watchExpenses().first;

      expect(expenses, hasLength(1));
      expect(expenses.single.expenseAccountId, 'food');
      expect(expenses.single.fromAccountId, 'cash');
      expect(expenses.single.amount, Decimal.parse('12.50'));
    });
  });

  group('queryActivityFeed', () {
    test('empty source reports no additional pages', () async {
      final page = await repo.queryActivityFeed(
        accountCategories: const {},
        pageSize: 10,
      );

      expect(page.entries, isEmpty);
      expect(page.hasMore, isFalse);
    });

    test('SQL filters with no matches report no additional pages', () async {
      await repo.create(
        entry: JournalEntryDraft(
          id: 'je-cash',
          date: DateTime.utc(2026, 5, 1),
          narration: 'Cash movement',
        ),
        postings: [cashLeg('cash', '-1'), cashLeg('food', '1')],
      );

      final page = await repo.queryActivityFeed(
        accountIds: {'missing-account'},
        accountCategories: const {},
        pageSize: 10,
      );

      expect(page.entries, isEmpty);
      expect(page.hasMore, isFalse);
    });

    test('uses SQL-backed date/account filters and keyset ordering', () async {
      await repo.create(
        entry: JournalEntryDraft(
          id: 'je-old',
          date: DateTime.utc(2026, 1, 1),
          narration: 'Old',
        ),
        postings: [cashLeg('cash', '-1'), cashLeg('food', '1')],
      );
      await repo.create(
        entry: JournalEntryDraft(
          id: 'je-new-a',
          date: DateTime.utc(2026, 5, 1),
          narration: 'New A',
        ),
        postings: [cashLeg('cash', '-2'), cashLeg('food', '2')],
      );
      await repo.create(
        entry: JournalEntryDraft(
          id: 'je-new-b',
          date: DateTime.utc(2026, 5, 1),
          narration: 'New B',
        ),
        postings: [cashLeg('bank', '-3'), cashLeg('food', '3')],
      );

      final page = await repo.queryActivityFeed(
        from: DateTime.utc(2026, 5),
        to: DateTime.utc(2026, 6),
        accountIds: {'cash'},
        accountCategories: const {},
        pageSize: 10,
      );

      expect(page.entries.map((e) => e.entry.id), ['je-new-a']);
      expect(page.hasMore, isFalse);
    });

    test('fills a page after derived kind filtering', () async {
      await repo.create(
        entry: JournalEntryDraft(
          id: 'je-transfer',
          date: DateTime.utc(2026, 5, 2),
          narration: 'Transfer',
        ),
        postings: [cashLeg('cash', '-1'), cashLeg('bank', '1')],
      );
      await repo.create(
        entry: JournalEntryDraft(
          id: 'je-expense',
          date: DateTime.utc(2026, 5, 1),
          narration: 'Expense',
        ),
        postings: [cashLeg('food', '2'), cashLeg('cash', '-2')],
      );

      final page = await repo.queryActivityFeed(
        kinds: {EntryKind.expense},
        accountCategories: const {
          'cash': AccountSide.asset,
          'bank': AccountSide.asset,
          'food': AccountSide.expense,
        },
        pageSize: 1,
      );

      expect(page.entries.map((e) => e.entry.id), ['je-expense']);
      expect(page.hasMore, isFalse);
    });
  });
}

Future<void> _insertAccount(
  AppDatabase db, {
  required String id,
  required AccountSide side,
  required AccountCategory type,
}) {
  return db
      .into(db.accounts)
      .insert(
        AccountsCompanion.insert(
          id: id,
          type: type,
          name: id,
          currency: 'USD',
          category: Value(side),
          ownerUserId: 'u-test',
          updatedAt: DateTime.utc(2026),
          updatedByDevice: 'dev-test',
          hlc: const Hlc(wallMillis: 1, counter: 0, nodeId: 'dev-test'),
        ),
      );
}
