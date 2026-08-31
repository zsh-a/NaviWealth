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

  test('filters all, ungrouped, and collection scopes', () async {
    final grouped = _item('us_stock:AAPL', 'AAPL');
    final ungrouped = _item('us_stock:MSFT', 'MSFT');
    final member = WatchlistCollectionMember(
      id: 'member-1',
      collectionId: 'collection-1',
      watchlistItemId: grouped.id,
      addedAt: DateTime.utc(2026, 5, 18),
      sync: grouped.sync,
    );
    final container = ProviderContainer(
      overrides: [
        watchlistItemsProvider.overrideWith(
          (_) => Stream.value([grouped, ungrouped]),
        ),
        watchlistCollectionMembersProvider.overrideWith(
          (_) => Stream.value([member]),
        ),
      ],
    );
    addTearDown(container.dispose);
    final itemsSub = container.listen(watchlistItemsProvider, (_, _) {});
    final membersSub = container.listen(
      watchlistCollectionMembersProvider,
      (_, _) {},
    );
    addTearDown(itemsSub.close);
    addTearDown(membersSub.close);

    expect(
      await container.read(
        watchlistItemsForScopeProvider(const WatchlistScope.all()).future,
      ),
      [grouped, ungrouped],
    );
    expect(
      await container.read(
        watchlistItemsForScopeProvider(const WatchlistScope.ungrouped()).future,
      ),
      [ungrouped],
    );
    expect(
      await container.read(
        watchlistItemsForScopeProvider(
          const WatchlistScope.collection('collection-1'),
        ).future,
      ),
      [grouped],
    );
  });

  test('summarizes available and directional quote snapshots', () {
    final advancing = _item('us_stock:AAPL', 'AAPL');
    final declining = _item('us_stock:MSFT', 'MSFT');
    final unchanged = _item('us_stock:GOOG', 'GOOG');
    final unavailable = _item('us_stock:NVDA', 'NVDA');
    final summary = WatchlistQuoteSummary.fromSnapshots(
      symbolCount: 4,
      snapshots: [
        _snapshot(advancing, price: '201', previousClose: '200'),
        _snapshot(declining, price: '199', previousClose: '200'),
        _snapshot(unchanged, price: '200', previousClose: '200'),
        WatchlistQuoteSnapshot(item: unavailable, error: StateError('offline')),
      ],
    );

    expect(summary.symbolCount, 4);
    expect(summary.availableQuoteCount, 3);
    expect(summary.advancingCount, 1);
    expect(summary.decliningCount, 1);
  });
}

WatchlistItem _item(String id, String symbol) => WatchlistItem(
  id: id,
  symbol: symbol,
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

WatchlistQuoteSnapshot _snapshot(
  WatchlistItem item, {
  required String price,
  required String previousClose,
}) => WatchlistQuoteSnapshot(
  item: item,
  response: MarketResponse(
    data: Quote(
      symbol: item.symbol,
      currency: 'USD',
      price: Decimal.parse(price),
      previousClose: Decimal.parse(previousClose),
      asOf: DateTime.utc(2026, 5, 18, 2),
    ),
    freshness: DataFreshness.cachedFresh,
    source: 'test-cache',
    fetchedAt: DateTime.utc(2026, 5, 18, 2),
  ),
);

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
