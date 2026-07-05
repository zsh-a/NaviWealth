import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/price_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/securities_asset_repository.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/domain/models/invariants.dart';
import 'package:naviwealth/features/finance/investment/application/trade_entry_submission_service.dart';
import 'package:naviwealth/features/finance/investment/domain/models/lot.dart';
import 'package:naviwealth/features/finance/investment/domain/trade_entry/trade_draft.dart';
import 'package:naviwealth/features/finance/investment/domain/trade_entry/trade_entry_plan.dart';
import 'package:naviwealth/features/finance/investment/domain/trade_entry/trade_entry_service.dart';
import 'package:naviwealth/features/finance/market/domain/asset_market.dart';

import '../../../../core/persistence/test_database.dart';
import '../../data/repositories/_stub_stamper.dart';

void main() {
  late AppDatabase db;
  late InMemoryOutboxStore outbox;
  late TradeEntrySubmissionService service;

  setUp(() {
    db = makeTestDatabase();
    outbox = InMemoryOutboxStore();
    final stamper = makeStubStamper();
    final securitiesRepo = SecuritiesAssetRepository(
      db: db,
      outbox: outbox,
      stamper: stamper,
    );
    final journalEntryRepo = JournalEntryRepository(
      db: db,
      outbox: outbox,
      stamper: stamper,
      fxRateSource: const IdentityFxRateSource(),
      baseCurrency: 'USD',
    );
    final priceRepo = PriceRepository(db: db, outbox: outbox, stamper: stamper);
    service = TradeEntrySubmissionService(
      securitiesRepo: securitiesRepo,
      tradeService: const _EchoTradeEntryService(),
      journalEntryRepo: journalEntryRepo,
      priceRepo: priceRepo,
      currentUserId: () async => 'u-test',
    );
  });

  tearDown(() async {
    await db.close();
  });

  test(
    'buy submission writes security asset, journal entry, and price',
    () async {
      await service.submit(
        TradeEntrySubmissionRequest(
          symbol: 'AAPL',
          market: AssetMarket.usStock,
          assetType: AssetType.stock,
          assetCurrency: 'USD',
          assetName: 'Apple Inc.',
          type: TradeType.buy,
          accountId: 'broker',
          cashAccountId: 'cash',
          quantity: Decimal.fromInt(10),
          price: Decimal.fromInt(150),
          currency: 'USD',
          tradeDate: DateTime.utc(2026, 5, 1),
          defaultNarration: (asset) => 'Buy 10 ${asset.symbol} (${asset.name})',
        ),
      );

      final assets = await db.select(db.assets).get();
      expect(assets, hasLength(1));
      expect(assets.single.id, 'us_stock:AAPL');

      final entries = await db.select(db.journalEntries).get();
      expect(entries, hasLength(1));
      expect(entries.single.narration, 'Buy 10 AAPL (Apple Inc.)');
      expect(entries.single.tagIdsJson, contains('asset:us_stock:AAPL'));

      final postings = await db.select(db.postings).get();
      expect(postings, hasLength(2));
      expect(postings.map((p) => p.accountId), containsAll(['broker', 'cash']));

      final prices = await db.select(db.prices).get();
      expect(prices, hasLength(1));
      expect(prices.single.unit, 'us_stock:AAPL');
      expect(prices.single.quoteCurrency, 'USD');
      expect(prices.single.perUnit, Decimal.fromInt(150));
      expect(prices.single.source, 'trade');
    },
  );
}

class _EchoTradeEntryService implements TradeEntryService {
  const _EchoTradeEntryService();

  @override
  Future<TradeEntryPlan> buildPlan(
    TradeDraft draft, {
    required List<Lot> openLots,
  }) async {
    return TradeEntryPlan(
      trade: PlannedTrade(
        id: draft.transactionId ?? 'tx-test',
        accountId: draft.accountId,
        assetId: draft.asset.id,
        type: draft.type,
        quantity: draft.quantity,
        price: draft.price ?? Decimal.one,
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
