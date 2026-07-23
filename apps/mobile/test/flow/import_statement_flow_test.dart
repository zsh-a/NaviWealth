// Flow / Task test: "Import CSV / statement" — Task #4 in
// docs/development/testing-strategy.md.
//
// This boots the real app shell, discovers the ingest review queue from
// Activity, pastes a small CSV statement, and proves the pipeline stages rows
// as explicit review drafts instead of silently committing them.

import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/auth/current_user.dart';
import 'package:naviwealth/features/finance/cashflow/data/cash_flow_ledger_adapters.dart';
import 'package:naviwealth/features/finance/cashflow/domain/cash_flow_aggregator.dart';
import 'package:naviwealth/features/finance/cashflow/domain/cash_flow_classifier.dart';
import 'package:naviwealth/features/finance/cashflow/domain/cash_flow_kind.dart';
import 'package:naviwealth/features/finance/data/repositories/account_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_repository.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/domain/models/invariants.dart';

import 'support/app_harness.dart';
import 'support/page_objects.dart';

void main() {
  group('Task: Import CSV / statement', () {
    late FlowDataHarness data;

    setUp(() async {
      data = await FlowDataHarness.create();
    });

    tearDown(() async {
      await data.dispose();
    });

    testWidgets('user reviews an import and can undo a skipped draft', (
      tester,
    ) async {
      await bootApp(tester, liveData: data);

      final shell = AppShell(tester)..expectMounted();
      await shell.openTab('Activity');

      final activity = ActivityPageObject(tester);
      await activity.openIngestQueue();

      final ingest = IngestReviewPageObject(tester);
      ingest.expectLandedEmpty();
      await ingest.pasteStatement(
        'date,description,amount,currency\n'
        '2026-05-10,STARBUCKS 04291,-38.00,CNY\n'
        '2026-05-12,Metro Groceries,-64.50,CNY\n',
      );

      ingest.expectDraftVisible('STARBUCKS 04291');
      ingest.expectDraftVisible('Metro Groceries');
      ingest.expectConfirmAllCount(2);
      final staged = await data.db
          .customSelect('SELECT owner_user_id, status FROM ingest_drafts')
          .get();
      expect(staged.map((row) => row.data['owner_user_id']).toSet(), {
        'local-user',
      });

      await ingest.skipDraft('STARBUCKS 04291');
      expect(find.textContaining('STARBUCKS 04291'), findsNothing);
      await ingest.undoLastAction();
      ingest.expectDraftVisible('STARBUCKS 04291');
      ingest.expectConfirmAllCount(2);
      await closeApp(tester);
    }, tags: 'flow');

    testWidgets(
      'expense and income reach cashflow and reimport as duplicates',
      (tester) async {
        final accountRepo = AccountRepository(
          db: data.db,
          outbox: data.outbox,
          stamper: data.stamper,
        );
        await accountRepo.create(
          type: AccountCategory.bank,
          name: 'Flow Checking',
          currency: 'CNY',
        );
        final journalRepo = JournalEntryRepository(
          db: data.db,
          outbox: data.outbox,
          stamper: data.stamper,
          fxRateSource: const IdentityFxRateSource(),
          baseCurrency: 'CNY',
        );
        const statement =
            'date,description,amount,currency,收/支\n'
            '2026-05-10,STARBUCKS 04291,-38.00,CNY,支出\n'
            '2026-05-12,Metro Groceries,-64.50,CNY,支出\n'
            '2026-05-31,Monthly salary,5000.00,CNY,收入\n';

        await bootApp(tester, liveData: data);

        final shell = AppShell(tester)..expectMounted();
        await shell.openTab('Activity');
        await ActivityPageObject(tester).openIngestQueue();

        final ingest = IngestReviewPageObject(tester);
        ingest.expectLandedEmpty();
        await ingest.pasteStatement(statement);
        ingest.expectConfirmAllCount(3);
        await ingest.confirmAllFresh(3);

        final expenses = (await tester.runAsync(
          () => journalRepo
              .watchExpenses(kLocalOnlyUserId)
              .firstWhere((rows) => rows.length == 2)
              .timeout(const Duration(seconds: 5)),
        ))!;
        expect(expenses.map((expense) => expense.amount.toString()).toSet(), {
          '38',
          '64.5',
        });

        final entries = (await tester.runAsync(
          () => journalRepo
              .watchAllWithPostings()
              .firstWhere((rows) => rows.length == 3)
              .timeout(const Duration(seconds: 5)),
        ))!;
        final accounts = (await tester.runAsync(
          () => accountRepo
              .watchActiveIncludingSystem(kLocalOnlyUserId)
              .firstWhere((rows) => rows.length >= 3)
              .timeout(const Duration(seconds: 5)),
        ))!;
        final accountsById = {
          for (final account in accounts) account.id: account,
        };
        final events = [
          for (final entry in entries)
            ?classifyCashFlowEvent(
              entry.toCashFlowLedgerEntry(),
              resolveAccount: (accountId) => accountsById[accountId],
            ),
        ];
        expect(events, hasLength(3));
        expect(events.map((event) => event.kind).toSet(), {
          CashFlowKind.expense,
          CashFlowKind.salary,
        });
        final summary = aggregateCashFlow(
          events,
          period: CashFlowPeriod.month,
          baseCurrency: 'CNY',
        );
        expect(summary.totalInBase.amount.toString(), '4897.5');

        await ingest.pasteStatement(statement, completionText: 'Duplicate');
        ingest.expectDraftVisible('STARBUCKS 04291');
        ingest.expectDraftVisible('Metro Groceries');
        ingest.expectDraftVisible('Monthly salary');
        ingest.expectDuplicateCount(3);

        final committedRows = await data.db
            .customSelect(
              'SELECT COUNT(*) AS count FROM journal_entries '
              'WHERE deleted_at IS NULL',
            )
            .getSingle();
        expect(committedRows.read<int>('count'), 3);
        await closeApp(tester);
      },
      tags: 'flow',
    );
  });
}
