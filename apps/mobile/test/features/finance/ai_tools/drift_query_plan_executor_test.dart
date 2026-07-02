import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/contracts/contracts.dart' show DateRange;
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/features/finance/ai_tools/drift_query_plan_executor.dart';
import 'package:naviwealth/features/finance/ai_tools/query_plan/query_plan.dart';
import 'package:naviwealth/features/finance/data/repositories/account_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_builders.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_providers.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_repository.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/domain/models/invariants.dart';

import '../../../core/persistence/test_database.dart';
import '../data/repositories/_stub_stamper.dart';

void main() {
  late AppDatabase db;
  late InMemoryOutboxStore outbox;
  late AccountRepository accountRepo;
  late JournalEntryRepository journalRepo;

  setUp(() async {
    db = makeTestDatabase();
    outbox = InMemoryOutboxStore();
    final stamper = makeStubStamper();
    accountRepo = AccountRepository(db: db, outbox: outbox, stamper: stamper);
    journalRepo = JournalEntryRepository(
      db: db,
      outbox: outbox,
      stamper: stamper,
      fxRateSource: const IdentityFxRateSource(),
      baseCurrency: 'CNY',
    );
    await accountRepo.seedSystemAccounts();
    await accountRepo.create(
      type: AccountCategory.cash,
      name: 'Wallet',
      currency: 'CNY',
    );
  });

  tearDown(() async => db.close());

  test('runs spending plans from real Drift expense rows', () async {
    await _recordExpense(
      journalRepo: journalRepo,
      fromAccountId: (await accountRepo.listActive()).single.id,
      categoryPath: 'expense:coffee',
      amount: '42.50',
      date: DateTime.utc(2026, 4, 15),
      note: 'STARBUCKS',
    );
    final expenses = await journalRepo.watchExpenses().first;
    expect(expenses, hasLength(1));
    expect(expenses.single.expenseAccountId, contains('expense:coffee'));

    final container = ProviderContainer(
      overrides: [
        journalEntryRepositoryProvider.overrideWith((_) async => journalRepo),
      ],
    );
    addTearDown(container.dispose);
    final expensesSub = container.listen(
      journalExpensesStreamProvider.future,
      (_, _) {},
    );
    addTearDown(expensesSub.close);
    expect(
      await container.read(journalExpensesStreamProvider.future),
      hasLength(1),
    );

    final executor = container.read(driftQueryPlanExecutorProvider);
    final result = await executor.run(
      const SpendingByCategoryPlan(
        range: DateRange(
          fromInclusive: '2026-04-01T00:00:00.000Z',
          toExclusive: '2026-05-01T00:00:00.000Z',
        ),
        categoryHints: <String>['coffee'],
      ),
    );

    expect(result.rows, hasLength(1));
    expect(result.rows.single.values['category'], 'coffee');
    expect(result.rows.single.values['amount_minor'], 4250);
    expect(result.summary?.totalAbsAmountMinor, 4250);
    expect(result.summary?.currency, 'CNY');
  });

  test('returns an empty result when the journal provider fails', () async {
    final container = ProviderContainer(
      overrides: [
        journalEntryRepositoryProvider.overrideWith((_) async {
          throw StateError('database unavailable');
        }),
      ],
    );
    addTearDown(container.dispose);

    final executor = container.read(driftQueryPlanExecutorProvider);
    final result = await executor.run(
      const TransactionsFilterPlan(
        range: DateRange(
          fromInclusive: '2026-04-01T00:00:00.000Z',
          toExclusive: '2026-05-01T00:00:00.000Z',
        ),
      ),
    );

    expect(result.rows, isEmpty);
  });
}

Future<void> _recordExpense({
  required JournalEntryRepository journalRepo,
  required String fromAccountId,
  required String categoryPath,
  required String amount,
  required DateTime date,
  required String note,
}) async {
  final expenseAccountId = AccountRepository.systemAccountIdForPath(
    categoryPath,
    ownerUserId: 'u-test',
  );
  final build = JournalEntryBuilders.expense(
    date: date,
    expenseAccountId: expenseAccountId,
    fromAccountId: fromAccountId,
    amount: Decimal.parse(amount),
    currency: 'CNY',
    narration: note,
  );
  await journalRepo.create(entry: build.entry, postings: build.postings);
}
