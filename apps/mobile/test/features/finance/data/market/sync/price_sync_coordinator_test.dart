import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/finance/data/market/exceptions.dart';
import 'package:naviwealth/features/finance/data/market/sync/fx_rate_sync_service.dart';
import 'package:naviwealth/features/finance/data/market/sync/price_sync_coordinator.dart';
import 'package:naviwealth/features/finance/data/repositories/fx_rate_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/price_repository.dart';
import 'package:naviwealth/features/finance/domain/models/asset.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/market/domain/asset_market.dart';
import 'package:naviwealth/features/finance/market/domain/historical_bar.dart';
import 'package:naviwealth/features/finance/market/domain/market_data_service.dart';
import 'package:naviwealth/features/finance/market/domain/quote.dart';
import 'package:naviwealth/features/finance/market/domain/symbol_info.dart';

import '../../../../../core/persistence/test_database.dart';
import '../../../../../core/sync/_outbox_test_ext.dart';
import '../../../../../features/finance/data/repositories/_stub_stamper.dart';
import '../fake_clock.dart';

class _RecordingMarket implements MarketDataService {
  final List<String> quotedSymbols = [];

  @override
  Future<MarketResponse<Quote>> getQuote(
    String symbol, {
    AssetMarket? market,
  }) async {
    quotedSymbols.add(symbol);
    return MarketResponse(
      data: Quote(
        symbol: symbol,
        currency: 'USD',
        price: Decimal.parse('100'),
        asOf: DateTime.utc(2026, 5, 14, 12),
      ),
      freshness: DataFreshness.live,
      source: 'fake',
      fetchedAt: DateTime.utc(2026, 5, 14, 12),
    );
  }

  @override
  Future<MarketResponse<List<HistoricalBar>>> getHistorical(
    String symbol, {
    required DateTime from,
    required DateTime to,
    BarInterval interval = BarInterval.day,
    AssetMarket? market,
  }) async => throw const NoMarketDataAvailableException('not used');

  @override
  Future<MarketResponse<List<SymbolInfo>>> searchSymbol(
    String query, {
    AssetMarket? market,
  }) async => throw UnimplementedError();
}

Asset _asset({
  required String symbol,
  required AssetType type,
  String market = 'us_stock',
  String currency = 'USD',
}) => Asset(
  id: '$market:$symbol',
  type: type,
  symbol: symbol,
  currency: currency,
  market: market,
  sync: SyncMeta(
    ownerUserId: 'u',
    updatedAt: DateTime.utc(2026, 1, 1),
    updatedByDevice: 'dev',
    hlc: const Hlc(wallMillis: 0, counter: 0, nodeId: 'dev'),
  ),
);

void main() {
  test(
    'triggerNow warms quotable assets and skips manual-valuation types',
    () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final market = _RecordingMarket();
      final fxRepo = FxRateRepository(db: db);
      final fxSync = FxRateSyncService(marketData: market, fxRepo: fxRepo);

      final coordinator = PriceSyncCoordinator(
        market: market,
        fxSync: fxSync,
        clock: FakeClock(),
        heldAssets: () async => [
          _asset(symbol: 'AAPL', type: AssetType.stock),
          _asset(symbol: 'BTC-USD', type: AssetType.crypto, market: 'crypto'),
          _asset(symbol: 'cash-cny', type: AssetType.cash, market: 'unknown'),
          _asset(
            symbol: 'house-1',
            type: AssetType.realEstate,
            market: 'unknown',
          ),
        ],
        fxInputs: () async =>
            const FxSyncInputs(baseCurrency: 'USD', currencies: {'USD'}),
      );

      await coordinator.triggerNow();

      // Cash + real estate are skipped; only AAPL + BTC-USD warmed.
      expect(market.quotedSymbols, contains('AAPL'));
      expect(market.quotedSymbols, contains('BTC-USD'));
      expect(market.quotedSymbols, isNot(contains('cash-cny')));
      expect(market.quotedSymbols, isNot(contains('house-1')));
      expect(coordinator.lastSuccessAt, isNotNull);
    },
  );

  test('concurrent triggerNow calls share the same in-flight cycle', () async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final market = _RecordingMarket();
    final fxRepo = FxRateRepository(db: db);
    final fxSync = FxRateSyncService(marketData: market, fxRepo: fxRepo);
    final coordinator = PriceSyncCoordinator(
      market: market,
      fxSync: fxSync,
      clock: FakeClock(),
      heldAssets: () async => [_asset(symbol: 'AAPL', type: AssetType.stock)],
      fxInputs: () async => null,
    );

    await Future.wait([
      coordinator.triggerNow(),
      coordinator.triggerNow(),
      coordinator.triggerNow(),
    ]);

    // Three concurrent calls collapsed to a single cycle.
    expect(coordinator.cycleCount, 1);
    expect(market.quotedSymbols, ['AAPL']);
  });

  test(
    'Phase E: writes one auto:<provider> snapshot per asset per UTC day',
    () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final market = _RecordingMarket();
      final fxRepo = FxRateRepository(db: db);
      final fxSync = FxRateSyncService(marketData: market, fxRepo: fxRepo);
      final outbox = InMemoryOutboxStore();
      final priceRepo = PriceRepository(
        db: db,
        outbox: outbox,
        stamper: makeStubStamper(),
      );
      final asset = _asset(symbol: 'AAPL', type: AssetType.stock);
      final coordinator = PriceSyncCoordinator(
        market: market,
        fxSync: fxSync,
        prices: priceRepo,
        writeDailySnapshots: () => true,
        clock: FakeClock(DateTime.utc(2026, 5, 14, 12)),
        heldAssets: () async => [asset],
        fxInputs: () async => null,
      );

      await coordinator.triggerNow();
      final firstBatch = outbox.queued;
      expect(firstBatch, hasLength(1));
      expect(firstBatch.single.table, 'prices');
      final recorded = await priceRepo.latestAt(
        unit: asset.id,
        quoteCurrency: 'USD',
        asOf: DateTime.utc(2026, 5, 14, 23, 59),
      );
      expect(
        recorded?.observedOn,
        DateTime.utc(2026, 5, 14, 12),
        reason: 'snapshot keeps the quote observation time',
      );

      // Second cycle on same UTC day → no new row written.
      await coordinator.triggerNow();
      final secondBatch = outbox.queued;
      expect(secondBatch, hasLength(1), reason: 'idempotent per day');
    },
  );

  test('Phase E: skipped when toggle is OFF', () async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final market = _RecordingMarket();
    final fxRepo = FxRateRepository(db: db);
    final fxSync = FxRateSyncService(marketData: market, fxRepo: fxRepo);
    final outbox = InMemoryOutboxStore();
    final priceRepo = PriceRepository(
      db: db,
      outbox: outbox,
      stamper: makeStubStamper(),
    );
    final coordinator = PriceSyncCoordinator(
      market: market,
      fxSync: fxSync,
      prices: priceRepo,
      writeDailySnapshots: () => false,
      clock: FakeClock(),
      heldAssets: () async => [_asset(symbol: 'AAPL', type: AssetType.stock)],
      fxInputs: () async => null,
    );

    await coordinator.triggerNow();
    expect(market.quotedSymbols, ['AAPL']);
    final batch = outbox.queued;
    expect(batch, isEmpty, reason: 'no outbox writes when toggle OFF');
  });

  test('Phase E: does not overwrite a same-day manual row', () async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final market = _RecordingMarket();
    final fxRepo = FxRateRepository(db: db);
    final fxSync = FxRateSyncService(marketData: market, fxRepo: fxRepo);
    final outbox = InMemoryOutboxStore();
    final priceRepo = PriceRepository(
      db: db,
      outbox: outbox,
      stamper: makeStubStamper(),
    );
    final asset = _asset(symbol: 'AAPL', type: AssetType.stock);
    // User already entered today's price manually.
    await priceRepo.record(
      unit: asset.id,
      quoteCurrency: 'USD',
      observedOn: DateTime.utc(2026, 5, 14, 10),
      perUnit: Decimal.parse('195.00'),
      source: 'manual',
    );
    // Drain the manual row from outbox so we only assert on cycle output.
    outbox.clearQueued();

    final coordinator = PriceSyncCoordinator(
      market: market,
      fxSync: fxSync,
      prices: priceRepo,
      writeDailySnapshots: () => true,
      clock: FakeClock(DateTime.utc(2026, 5, 14, 12)),
      heldAssets: () async => [asset],
      fxInputs: () async => null,
    );
    await coordinator.triggerNow();

    final after = outbox.queued;
    expect(after, isEmpty, reason: 'manual row wins, no auto row written');
  });

  test('mutation hook debounces rapid bursts into a single cycle', () async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final market = _RecordingMarket();
    final fxRepo = FxRateRepository(db: db);
    final fxSync = FxRateSyncService(marketData: market, fxRepo: fxRepo);
    final coordinator = PriceSyncCoordinator(
      market: market,
      fxSync: fxSync,
      clock: FakeClock(),
      heldAssets: () async => [_asset(symbol: 'AAPL', type: AssetType.stock)],
      fxInputs: () async => null,
    );

    coordinator.onMutationAffectingHoldings();
    coordinator.onMutationAffectingHoldings();
    coordinator.onMutationAffectingHoldings();

    // Wait past the 2s debounce window.
    await Future<void>.delayed(const Duration(seconds: 3));

    expect(coordinator.cycleCount, 1);
    addTearDown(coordinator.stop);
  });
}
