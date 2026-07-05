import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/assets/data/asset_detail_providers.dart';
import 'package:naviwealth/features/finance/data/market/market_data_providers.dart';
import 'package:naviwealth/features/finance/investment/data/providers.dart';
import 'package:naviwealth/features/finance/investment/domain/holding_service.dart';
import 'package:naviwealth/features/finance/investment/domain/models/holding_snapshot.dart';
import 'package:naviwealth/features/finance/investment/domain/models/lot.dart';
import 'package:naviwealth/features/finance/market/domain/asset_market.dart';
import 'package:naviwealth/features/finance/market/domain/historical_bar.dart';
import 'package:naviwealth/features/finance/market/domain/market_data_service.dart';
import 'package:naviwealth/features/finance/market/domain/quote.dart';
import 'package:naviwealth/features/finance/market/domain/symbol_info.dart';

void main() {
  group('PriceHistoryKey', () {
    test('is value-equal by symbol, market, and lookback window', () {
      const key = PriceHistoryKey(
        symbol: 'AAPL',
        market: AssetMarket.usStock,
        days: 30,
      );

      expect(
        key,
        const PriceHistoryKey(
          symbol: 'AAPL',
          market: AssetMarket.usStock,
          days: 30,
        ),
      );
      expect(
        key.hashCode,
        const PriceHistoryKey(
          symbol: 'AAPL',
          market: AssetMarket.usStock,
          days: 30,
        ).hashCode,
      );
      expect(
        key,
        isNot(
          const PriceHistoryKey(
            symbol: 'AAPL',
            market: AssetMarket.usStock,
            days: 90,
          ),
        ),
      );
      expect(
        key,
        isNot(
          const PriceHistoryKey(
            symbol: 'AAPL',
            market: AssetMarket.cnA,
            days: 30,
          ),
        ),
      );
    });
  });

  group('assetPriceHistoryProvider', () {
    test(
      'passes symbol, market, and lookback window to market service',
      () async {
        final market = _RecordingMarketDataService();
        final container = ProviderContainer(
          overrides: [
            marketDataServiceProvider.overrideWith((_) async => market),
          ],
        );
        addTearDown(container.dispose);

        final response = await container.read(
          assetPriceHistoryProvider(
            const PriceHistoryKey(
              symbol: 'AAPL',
              market: AssetMarket.usStock,
              days: 45,
            ),
          ).future,
        );

        expect(response.source, 'test-market');
        expect(response.data.single.close, Decimal.parse('101'));
        expect(market.lastHistoricalSymbol, 'AAPL');
        expect(market.lastHistoricalMarket, AssetMarket.usStock);
        expect(market.lastHistoricalInterval, BarInterval.day);
        expect(
          market.lastHistoricalTo!.difference(market.lastHistoricalFrom!),
          const Duration(days: 45),
        );
      },
    );

    test(
      'preserves null market for assets without a linked exchange',
      () async {
        final market = _RecordingMarketDataService();
        final container = ProviderContainer(
          overrides: [
            marketDataServiceProvider.overrideWith((_) async => market),
          ],
        );
        addTearDown(container.dispose);

        await container.read(
          assetPriceHistoryProvider(
            const PriceHistoryKey(symbol: 'BTC', market: null, days: 7),
          ).future,
        );

        expect(market.lastHistoricalSymbol, 'BTC');
        expect(market.lastHistoricalMarket, isNull);
        expect(
          market.lastHistoricalTo!.difference(market.lastHistoricalFrom!),
          const Duration(days: 7),
        );
      },
    );
  });

  group('assetHoldingSnapshotProvider', () {
    test(
      'returns the requested asset snapshot and null for unknown assets',
      () async {
        final snapshot = _snapshot('asset-a');
        final holdingService = _MapHoldingService({'asset-a': snapshot});
        final container = ProviderContainer(
          overrides: [
            holdingServiceProvider.overrideWith((_) async => holdingService),
          ],
        );
        addTearDown(container.dispose);

        await expectLater(
          container.read(assetHoldingSnapshotProvider('asset-a').future),
          completion(snapshot),
        );
        await expectLater(
          container.read(assetHoldingSnapshotProvider('asset-b').future),
          completion(isNull),
        );
      },
    );
  });
}

class _RecordingMarketDataService implements MarketDataService {
  String? lastHistoricalSymbol;
  DateTime? lastHistoricalFrom;
  DateTime? lastHistoricalTo;
  BarInterval? lastHistoricalInterval;
  AssetMarket? lastHistoricalMarket;

  @override
  Future<MarketResponse<List<HistoricalBar>>> getHistorical(
    String symbol, {
    required DateTime from,
    required DateTime to,
    BarInterval interval = BarInterval.day,
    AssetMarket? market,
  }) async {
    lastHistoricalSymbol = symbol;
    lastHistoricalFrom = from;
    lastHistoricalTo = to;
    lastHistoricalInterval = interval;
    lastHistoricalMarket = market;
    return MarketResponse(
      data: [
        HistoricalBar(
          symbol: symbol,
          asOf: DateTime.utc(2026, 1, 1),
          open: Decimal.parse('100'),
          high: Decimal.parse('102'),
          low: Decimal.parse('99'),
          close: Decimal.parse('101'),
        ),
      ],
      freshness: DataFreshness.live,
      source: 'test-market',
      fetchedAt: DateTime.utc(2026, 1, 2),
    );
  }

  @override
  Future<MarketResponse<Quote>> getQuote(String symbol, {AssetMarket? market}) {
    throw UnimplementedError();
  }

  @override
  Future<MarketResponse<List<SymbolInfo>>> searchSymbol(
    String query, {
    AssetMarket? market,
  }) {
    throw UnimplementedError();
  }
}

class _MapHoldingService implements HoldingService {
  const _MapHoldingService(this.snapshots);

  final Map<String, HoldingSnapshot> snapshots;

  @override
  Future<Map<String, HoldingSnapshot>> computeAt(DateTime asOf) async =>
      snapshots;

  @override
  Future<void> invalidateFrom(DateTime from) async {}

  @override
  Future<List<Lot>> lotsAt(DateTime asOf) async => const [];

  @override
  Future<LotInventorySnapshot> persistDailySnapshot(DateTime day) async =>
      LotInventorySnapshot(ownerUserId: 'test', day: day, lots: const []);
}

HoldingSnapshot _snapshot(String assetId) {
  return HoldingSnapshot(
    assetId: assetId,
    quantity: Decimal.one,
    costBasisInAssetCurrency: Decimal.parse('100'),
    marketValueInAssetCurrency: Decimal.parse('120'),
    assetCurrency: 'USD',
    costBasisInBase: Decimal.parse('100'),
    marketValueInBase: Decimal.parse('120'),
    unrealizedPnlInBase: Decimal.parse('20'),
    weight: Decimal.zero,
    baseCurrency: 'USD',
    asOf: DateTime.utc(2026, 1, 2),
  );
}
