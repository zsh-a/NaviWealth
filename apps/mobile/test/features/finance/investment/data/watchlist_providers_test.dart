import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/finance/data/market/market_data_providers.dart';
import 'package:naviwealth/features/finance/investment/data/watchlist_providers.dart';
import 'package:naviwealth/features/finance/investment/data/watchlist_repository.dart';
import 'package:naviwealth/features/finance/market/domain/asset_market.dart';
import 'package:naviwealth/features/finance/market/domain/historical_bar.dart';
import 'package:naviwealth/features/finance/market/domain/market_data_service.dart';
import 'package:naviwealth/features/finance/market/domain/quote.dart';
import 'package:naviwealth/features/finance/market/domain/symbol_info.dart';

void main() {
  test('loads quote snapshots from overridden watchlist data source', () async {
    final item = WatchlistItem(
      id: 'us_stock:AAPL',
      symbol: 'AAPL',
      market: AssetMarket.usStock,
      addedAt: DateTime.utc(2026, 5, 18),
      alertRules: const PriceAlertRules(),
      sync: SyncMeta(
        ownerUserId: 'u-test',
        updatedAt: DateTime.utc(2026, 5, 18),
        updatedByDevice: 'dev-test',
        hlc: Hlc.zero('dev-test'),
      ),
    );
    final container = ProviderContainer(
      overrides: [
        watchlistItemsProvider.overrideWith((_) => Stream.value([item])),
        marketDataServiceProvider.overrideWith(
          (_) async => _FakeMarketDataService(),
        ),
      ],
    );
    addTearDown(container.dispose);
    final itemsSub = container.listen(watchlistItemsProvider, (_, _) {});
    addTearDown(itemsSub.close);

    final snapshots = await container.read(
      watchlistQuoteSnapshotsProvider.future,
    );

    expect(snapshots, hasLength(1));
    expect(snapshots.single.item.id, item.id);
    expect(snapshots.single.response?.freshness, DataFreshness.cachedFresh);
    expect(snapshots.single.quote?.price, Decimal.parse('201.25'));
  });
}

class _FakeMarketDataService implements MarketDataService {
  @override
  Future<MarketResponse<Quote>> getQuote(
    String symbol, {
    AssetMarket? market,
  }) async {
    return MarketResponse(
      data: Quote(
        symbol: symbol,
        currency: 'USD',
        price: Decimal.parse('201.25'),
        asOf: DateTime.utc(2026, 5, 18, 2),
      ),
      freshness: DataFreshness.cachedFresh,
      source: 'test-cache',
      fetchedAt: DateTime.utc(2026, 5, 18, 2),
    );
  }

  @override
  Future<MarketResponse<List<HistoricalBar>>> getHistorical(
    String symbol, {
    required DateTime from,
    required DateTime to,
    BarInterval interval = BarInterval.day,
    AssetMarket? market,
  }) {
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
