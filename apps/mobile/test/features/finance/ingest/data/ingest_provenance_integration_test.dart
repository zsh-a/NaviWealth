import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/features/finance/application/finance_core_proposal_applier.dart';
import 'package:naviwealth/features/finance/data/repositories/account_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_builders.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/manual_asset_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/price_repository.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/domain/models/invariants.dart';
import 'package:naviwealth/features/finance/expense/data/expense_category_repository.dart';
import 'package:naviwealth/features/finance/ingest/data/ingest_confirm_service.dart';
import 'package:naviwealth/features/finance/ingest/data/ingest_dedup.dart';
import 'package:naviwealth/features/finance/ingest/data/ingest_dedup_service.dart';
import 'package:naviwealth/features/finance/ingest/data/ingest_draft_store.dart';
import 'package:naviwealth/features/finance/ingest/domain/ingest_models.dart';
import 'package:naviwealth/features/finance/ingest/domain/ingest_source_reference.dart';
import 'package:naviwealth/features/finance/liabilities/data/liability_repository.dart';

import '../../../../core/persistence/test_database.dart';
import '../../data/repositories/_stub_stamper.dart';

void main() {
  test(
    'trade fees remain expense evidence without borrowing principal identity',
    () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final store = IngestDraftStore(db, ownerUserId: 'u-test');
      addTearDown(store.dispose);
      final outbox = DriftOutboxStore(db);
      final stamper = makeStubStamper();
      final accounts = AccountRepository(
        db: db,
        outbox: outbox,
        stamper: stamper,
      );
      await accounts.seedSystemAccounts();
      final cash = await accounts.create(
        type: AccountCategory.bank,
        name: 'Cash',
        currency: 'CNY',
      );
      final broker = await accounts.create(
        type: AccountCategory.broker,
        name: 'Broker',
        currency: 'CNY',
      );
      await ExpenseCategoryRepository(
        db: db,
        outbox: outbox,
        stamper: stamper,
      ).seedDefaults('u-test');
      final journal = JournalEntryRepository(
        db: db,
        outbox: outbox,
        stamper: stamper,
        fxRateSource: const IdentityFxRateSource(),
        baseCurrency: 'CNY',
      );
      final date = DateTime.utc(2026, 6, 18, 10);
      final build = JournalEntryBuilders.buy(
        date: date,
        accountId: broker.id,
        cashAccountId: cash.id,
        assetUnit: 'AAPL',
        qty: Decimal.one,
        price: Decimal.fromInt(18),
        quoteCurrency: 'CNY',
        feeAmount: Decimal.one,
        feeAccountId: AccountRepository.systemAccountIdForPath(
          'expense:trading:fee',
          ownerUserId: 'u-test',
        ),
        narration: 'Trade fee',
        tagIds: ingestProvenanceTags(
          kind: 'trade',
          reference: const IngestSourceReference(
            provider: 'broker',
            transactionId: 'trade-1/trade',
            account: 'source-broker-a',
          ),
        ),
      );
      final recorded = await journal.create(
        entry: build.entry,
        postings: build.postings,
      );
      final ledger = await IngestDedupService(
        store: store,
        repository: journal,
      ).readLedger();
      final duplicate = classifyDedup(
        ParsedTransaction(
          description: 'Trade fee',
          amountMinor: -100,
          currency: 'CNY',
          occurredAt: date,
          sourceReference: const IngestSourceReference(
            provider: 'broker',
            transactionId: 'trade-1/expense',
            account: 'source-broker-a',
          ),
        ),
        ledger,
      );
      expect(duplicate.verdict, DedupVerdict.duplicate);
      expect(duplicate.targetEntryId, recorded.entry.id);
    },
  );

  for (final kind in [
    IngestTransactionKind.expense,
    IngestTransactionKind.income,
  ]) {
    test(
      '${kind.wire} confirmation persists source identity for later exports',
      () async {
        final db = makeTestDatabase();
        addTearDown(db.close);
        final store = IngestDraftStore(db, ownerUserId: 'u-test');
        addTearDown(store.dispose);
        final outbox = DriftOutboxStore(db);
        final stamper = makeStubStamper();
        final accounts = AccountRepository(
          db: db,
          outbox: outbox,
          stamper: stamper,
        );
        await accounts.seedSystemAccounts();
        final account = await accounts.create(
          type: AccountCategory.bank,
          name: 'Daily account',
          currency: 'CNY',
        );
        final categories = ExpenseCategoryRepository(
          db: db,
          outbox: outbox,
          stamper: stamper,
        );
        await categories.seedDefaults('u-test');
        final journal = JournalEntryRepository(
          db: db,
          outbox: outbox,
          stamper: stamper,
          fxRateSource: const IdentityFxRateSource(),
          baseCurrency: 'CNY',
        );
        final applier = FinanceCoreProposalApplier(
          journalEntryRepo: journal,
          accountRepo: accounts,
          manualAssetRepo: ManualAssetRepository(
            db: db,
            outbox: outbox,
            stamper: stamper,
            priceRepo: PriceRepository(
              db: db,
              outbox: outbox,
              stamper: stamper,
            ),
          ),
          liabilityRepo: LiabilityRepository(
            db: db,
            outbox: outbox,
            stamper: stamper,
            journalEntryRepo: journal,
          ),
          expenseCategoryRepo: categories,
          currentUserId: () async => 'u-test',
        );
        final parsed = ParsedTransaction(
          description: 'Imported merchant',
          amountMinor: kind == IngestTransactionKind.expense ? -1800 : 1800,
          currency: 'CNY',
          occurredAt: DateTime.utc(2026, 6, 18, 10, 30, 45),
          kind: kind,
          categoryHint: kind == IngestTransactionKind.expense
              ? 'dining'
              : 'salary',
          sourceReference: IngestSourceReference(
            provider: 'wechatPay',
            transactionId: 'private-order-${kind.wire}',
          ),
        );
        final draft = IngestDraft(
          draftId: 'draft',
          ownerUserId: 'u-test',
          createdAt: parsed.occurredAt,
          sourceKind: IngestSourceKind.csv,
          parsed: parsed,
          verdict: DedupVerdict.newTxn,
          status: DraftStatus.pending,
        );
        final plan = IngestConfirmService.planFor(draft, accountId: account.id);
        final state = kind == IngestTransactionKind.expense
            ? await applier.applyExpense(plan, DateTime.utc(2026, 6, 19))
            : await applier.applyIncome(plan, DateTime.utc(2026, 6, 19));
        final recorded = (await journal.getById(state.appliedEntityId!))!;
        expect(recorded.entry.date.isAtSameMomentAs(parsed.occurredAt), isTrue);
        expect(
          ingestTagValue(recorded.entry.tagIds, ingestIdentityTagPrefix),
          parsed.sourceReference!.identity,
        );
        expect(recorded.entry.tagIds.join(), isNot(contains('private-order')));
        final ledger = await IngestDedupService(
          store: store,
          repository: journal,
        ).readLedger();
        expect(ledger.single.accountId, account.id);
        final corrected = parsed.copyWith(
          description: 'Corrected merchant',
          amountMinor: parsed.amountMinor * 2,
          occurredAt: DateTime.utc(2026, 7, 18),
        );
        final duplicate = classifyDedup(corrected, ledger);
        expect(duplicate.verdict, DedupVerdict.duplicate);
        expect(duplicate.targetEntryId, recorded.entry.id);
      },
    );
  }
}
