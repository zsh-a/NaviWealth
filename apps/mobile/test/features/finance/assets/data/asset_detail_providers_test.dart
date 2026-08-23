import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/assets/data/asset_detail_providers.dart';
import 'package:naviwealth/features/finance/data/market/market_data_providers.dart';
import 'package:naviwealth/features/finance/data/market/sync/price_sync_coordinator.dart';
import 'package:naviwealth/features/finance/data/market/sync/price_sync_providers.dart';
import 'package:naviwealth/features/finance/investment/data/providers.dart';
import 'package:naviwealth/features/finance/investment/domain/models/holding_snapshot.dart';
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

    test('refreshes after a successful background price sync', () async {
      final market = _RecordingMarketDataService();
      final statusBus = PriceSyncStatusBus();
      final container = ProviderContainer(
        overrides: [
          marketDataServiceProvider.overrideWith((_) async => market),
          priceSyncStatusBusProvider.overrideWithValue(statusBus),
        ],
      );
      addTearDown(statusBus.close);
      addTearDown(container.dispose);
      final provider = assetPriceHistoryProvider(
        const PriceHistoryKey(
          symbol: 'AAPL',
          market: AssetMarket.usStock,
          days: 30,
        ),
      );
      final subscription = container.listen(provider, (_, _) {});
      addTearDown(subscription.close);

      await container.read(provider.future);
      final callsBeforeSync = market.historicalCalls;

      final syncedAt = DateTime.utc(2026, 1, 3);
      statusBus.emit(
        PriceSyncStatusEvent(
          status: PriceSyncStatus.fresh,
          at: syncedAt,
          lastSuccessAt: syncedAt,
        ),
      );
      await pumpEventQueue();
      await container.read(provider.future);

      expect(market.historicalCalls, greaterThan(callsBeforeSync));
    });
  });

  group('assetHoldingSnapshotProvider', () {
    test(
      'returns the requested asset snapshot and null for unknown assets',
      () async {
        final snapshot = _snapshot('asset-a');
        final container = ProviderContainer(
          overrides: [
            holdingsSnapshotProvider.overrideWith(
              (_) async => {'asset-a': snapshot},
            ),
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

    test('updates when the shared holdings snapshot changes', () async {
      final holdingsState = StateProvider<Map<String, HoldingSnapshot>>(
        (_) => {'asset-a': _snapshot('asset-a')},
      );
      final container = ProviderContainer(
        overrides: [
          holdingsSnapshotProvider.overrideWith(
            (ref) async => ref.watch(holdingsState),
          ),
        ],
      );
      addTearDown(container.dispose);
      final provider = assetHoldingSnapshotProvider('asset-a');
      final subscription = container.listen(provider, (_, _) {});
      addTearDown(subscription.close);

      expect(
        (await container.read(provider.future))!.marketValueInBase,
        Decimal.parse('120'),
      );

      container.read(holdingsState.notifier).state = {
        'asset-a': _snapshot('asset-a', marketValue: '150'),
      };
      await pumpEventQueue();

      expect(
        (await container.read(provider.future))!.marketValueInBase,
        Decimal.parse('150'),
      );
    });
  });
}

class _RecordingMarketDataService implements MarketDataService {
  int historicalCalls = 0;
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
    historicalCalls += 1;
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

HoldingSnapshot _snapshot(String assetId, {String marketValue = '120'}) {
  final value = Decimal.parse(marketValue);
  return HoldingSnapshot(
    assetId: assetId,
    quantity: Decimal.one,
    costBasisInAssetCurrency: Decimal.parse('100'),
    marketValueInAssetCurrency: value,
    assetCurrency: 'USD',
    costBasisInBase: Decimal.parse('100'),
    marketValueInBase: value,
    unrealizedPnlInBase: value - Decimal.parse('100'),
    weight: Decimal.zero,
    baseCurrency: 'USD',
    asOf: DateTime.utc(2026, 1, 2),
  );
}
