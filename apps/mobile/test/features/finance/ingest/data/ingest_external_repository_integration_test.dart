import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_builders.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/price_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/securities_asset_repository.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/domain/models/invariants.dart';
import 'package:naviwealth/features/finance/ingest/data/ingest_draft_store.dart';
import 'package:naviwealth/features/finance/ingest/data/ingest_external_confirmation_coordinator.dart';
import 'package:naviwealth/features/finance/ingest/domain/ingest_models.dart';
import 'package:naviwealth/features/finance/investment/application/trade_entry_submission_service.dart';
import 'package:naviwealth/features/finance/investment/domain/models/lot.dart';
import 'package:naviwealth/features/finance/investment/domain/trade_entry/trade_draft.dart';
import 'package:naviwealth/features/finance/investment/domain/trade_entry/trade_entry_plan.dart';
import 'package:naviwealth/features/finance/investment/domain/trade_entry/trade_entry_service.dart';
import 'package:naviwealth/features/finance/market/domain/asset_market.dart';

import '../../../../core/persistence/test_database.dart';
import '../../data/repositories/_stub_stamper.dart';

IngestDraft _draft(IngestTransactionKind kind) => IngestDraft(
  draftId: '${kind.wire}-import-1',
  ownerUserId: 'u-test',
  createdAt: DateTime.utc(2026, 8, 30),
  sourceKind: IngestSourceKind.csv,
  parsed: ParsedTransaction(
    description: kind == IngestTransactionKind.trade
        ? 'AAPL valuation import'
        : 'Transfer to savings',
    amountMinor: kind == IngestTransactionKind.trade ? 15000 : -10000,
    currency: kind == IngestTransactionKind.trade ? 'USD' : 'CNY',
    occurredAt: DateTime.utc(2026, 8, 29),
    kind: kind,
  ),
  verdict: DedupVerdict.newTxn,
  status: DraftStatus.pending,
);

JournalEntryDraft _withId(JournalEntryDraft draft, String id) {
  return JournalEntryDraft(
    id: id,
    date: draft.date,
    settledOn: draft.settledOn,
    narration: draft.narration,
    payee: draft.payee,
    tagIds: draft.tagIds,
    flag: draft.flag,
  );
}

Future<void> _seedAccount(
  AppDatabase db, {
  required String id,
  required String name,
  required AccountCategory type,
  required String currency,
}) {
  return db
      .into(db.accounts)
      .insert(
        AccountsCompanion.insert(
          id: id,
          type: type,
          name: name,
          currency: currency,
          category: const Value(AccountSide.asset),
          ownerUserId: 'u-test',
          updatedAt: DateTime.utc(2026),
          updatedByDevice: 'dev-test',
          hlc: const Hlc(wallMillis: 1, counter: 0, nodeId: 'dev-test'),
        ),
      );
}

JournalEntryRepository _journalRepository(AppDatabase db) {
  return JournalEntryRepository(
    db: db,
    outbox: DriftOutboxStore(db),
    stamper: makeStubStamper(),
    fxRateSource: const IdentityFxRateSource(),
    baseCurrency: 'USD',
  );
}

TradeEntrySubmissionService _tradeSubmissionService(AppDatabase db) {
  final outbox = DriftOutboxStore(db);
  final stamper = makeStubStamper();
  return TradeEntrySubmissionService(
    db: db,
    securitiesRepo: SecuritiesAssetRepository(
      db: db,
      outbox: outbox,
      stamper: stamper,
    ),
    tradeService: const _ValuationTradeService(),
    journalEntryRepo: JournalEntryRepository(
      db: db,
      outbox: outbox,
      stamper: stamper,
      fxRateSource: const IdentityFxRateSource(),
      baseCurrency: 'USD',
    ),
    priceRepo: PriceRepository(db: db, outbox: outbox, stamper: stamper),
    currentUserId: () async => 'u-test',
  );
}

class _ValuationTradeService implements TradeEntryService {
  const _ValuationTradeService();

  @override
  Future<TradeEntryPlan> buildPlan(
    TradeDraft draft, {
    required List<Lot> openLots,
  }) async {
    return TradeEntryPlan(
      trade: PlannedTrade(
        id: draft.transactionId!,
        accountId: draft.accountId,
        assetId: draft.asset.id,
        type: draft.type,
        quantity: draft.quantity,
        price: draft.price!,
        currency: draft.currency,
        tradeDate: draft.tradeDate,
        fee: draft.fee,
        tax: draft.tax,
        note: draft.note,
      ),
      pricing: PriceProvenance.userSupplied,
    );
  }
}

void main() {
  test(
    'transfer repository mutation and ingest lifecycle share atomic Undo',
    () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      await _seedAccount(
        db,
        id: 'bank-a',
        name: 'Bank A',
        type: AccountCategory.bank,
        currency: 'CNY',
      );
      await _seedAccount(
        db,
        id: 'bank-b',
        name: 'Bank B',
        type: AccountCategory.bank,
        currency: 'CNY',
      );
      final draft = _draft(IngestTransactionKind.transfer);
      final store = IngestDraftStore(db, ownerUserId: 'u-test');
      addTearDown(store.dispose);
      await store.putAll([draft]);
      final coordinator = IngestExternalConfirmationCoordinator(store: store);
      final repository = _journalRepository(db);
      final build = JournalEntryBuilders.transfer(
        date: draft.parsed.occurredAt,
        fromAccountId: 'bank-a',
        toAccountId: 'bank-b',
        amount: Decimal.fromInt(100),
        currency: 'CNY',
        narration: draft.parsed.description,
      );

      final commit = await coordinator.confirm<JournalMutationReceipt>(
        draft,
        kind: IngestExternalKind.transfer,
        apply: (operationToken) => repository.createWithReceipt(
          entry: _withId(build.entry, operationToken),
          postings: build.postings,
        ),
        entityId: (receipt) => receipt.after.entry.id,
      );

      expect(commit.receipt.after.entry.id, commit.operationToken);
      expect(await store.countByStatus(DraftStatus.confirmed), 1);
      expect(await db.select(db.journalEntries).get(), hasLength(1));
      expect(await db.select(db.postings).get(), hasLength(2));

      await coordinator.undo<JournalMutationReceipt>(
        commit,
        undoMutation: repository.undoMutation,
      );

      expect(await store.countByStatus(DraftStatus.pending), 1);
      expect(
        (await db.select(db.journalEntries).getSingle()).deletedAt,
        isNotNull,
      );
      expect(
        (await db.select(db.postings).get()).every(
          (posting) => posting.deletedAt != null,
        ),
        isTrue,
      );
    },
  );

  test(
    'trade service mutation and ingest lifecycle share identity and Undo',
    () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      await _seedAccount(
        db,
        id: 'broker',
        name: 'Broker',
        type: AccountCategory.broker,
        currency: 'USD',
      );
      final draft = _draft(IngestTransactionKind.trade);
      final store = IngestDraftStore(db, ownerUserId: 'u-test');
      addTearDown(store.dispose);
      await store.putAll([draft]);
      final coordinator = IngestExternalConfirmationCoordinator(store: store);
      final service = _tradeSubmissionService(db);

      const operationToken = 'trade-operation-1';
      final prepared = await service.prepare(
        TradeEntrySubmissionRequest(
          transactionId: operationToken,
          symbol: 'AAPL',
          market: AssetMarket.usStock,
          assetType: AssetType.stock,
          assetCurrency: 'USD',
          assetName: 'Apple',
          type: TradeType.valuationAdjust,
          accountId: 'broker',
          quantity: Decimal.one,
          price: Decimal.fromInt(150),
          currency: 'USD',
          tradeDate: draft.parsed.occurredAt,
          note: draft.parsed.description,
          defaultNarration: (_) => draft.parsed.description,
        ),
      );
      final commit = await coordinator.confirm<TradeMutationReceipt>(
        draft,
        kind: IngestExternalKind.trade,
        operationToken: operationToken,
        apply: (_) => service.commit(prepared),
        entityId: (receipt) => receipt.journal.after.entry.id,
      );

      expect(commit.receipt.transactionId, commit.operationToken);
      expect(commit.receipt.journal.after.entry.id, commit.operationToken);
      expect(await store.countByStatus(DraftStatus.confirmed), 1);
      expect(
        (await db.select(db.prices).getSingle()).id,
        commit.operationToken,
      );

      await coordinator.undo<TradeMutationReceipt>(
        commit,
        undoMutation: service.undoMutation,
      );

      expect(await store.countByStatus(DraftStatus.pending), 1);
      expect(
        (await db.select(db.journalEntries).getSingle()).deletedAt,
        isNotNull,
      );
      expect((await db.select(db.prices).getSingle()).deletedAt, isNotNull);
      expect((await db.select(db.assets).getSingle()).deletedAt, isNull);
    },
  );
}
