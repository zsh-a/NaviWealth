import 'package:decimal/decimal.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/finance/investment/data/watchlist_providers.dart';
import 'package:naviwealth/features/finance/investment/data/watchlist_repository.dart';
import 'package:naviwealth/features/finance/investment/ui/watchlist_page.dart';
import 'package:naviwealth/features/finance/market/domain/asset_market.dart';
import 'package:naviwealth/features/finance/market/domain/market_data_service.dart';
import 'package:naviwealth/features/finance/market/domain/quote.dart';

import '_golden_setup.dart';

Decimal _d(String value) => Decimal.parse(value);

SyncMeta _meta() => SyncMeta(
  ownerUserId: 'u',
  updatedAt: DateTime.utc(2026, 5, 18),
  updatedByDevice: 'golden',
  hlc: Hlc.zero('golden'),
);

final _items = [
  WatchlistItem(
    id: 'us_stock:AAPL',
    symbol: 'AAPL',
    market: AssetMarket.usStock,
    addedAt: DateTime.utc(2026, 5, 18),
    alertRules: PriceAlertRules(above: _d('210'), below: _d('180')),
    sync: _meta(),
  ),
  WatchlistItem(
    id: 'hk_stock:2800.HK',
    symbol: '2800.HK',
    market: AssetMarket.hkStock,
    addedAt: DateTime.utc(2026, 5, 18, 1),
    alertRules: PriceAlertRules(below: _d('18')),
    sync: _meta(),
  ),
];

final _snapshots = [
  WatchlistQuoteSnapshot(
    item: _items[0],
    response: MarketResponse(
      data: Quote(
        symbol: 'AAPL',
        currency: 'USD',
        price: _d('201.25'),
        previousClose: _d('200'),
        asOf: DateTime.utc(2026, 5, 18, 2),
      ),
      freshness: DataFreshness.cachedFresh,
      source: 'golden-cache',
      fetchedAt: DateTime.utc(2026, 5, 18, 2),
    ),
  ),
  WatchlistQuoteSnapshot(
    item: _items[1],
    response: MarketResponse(
      data: Quote(
        symbol: '2800.HK',
        currency: 'HKD',
        price: _d('18.42'),
        previousClose: _d('19'),
        asOf: DateTime.utc(2026, 5, 18, 2),
      ),
      freshness: DataFreshness.stale,
      source: 'golden-cache',
      fetchedAt: DateTime.utc(2026, 5, 18, 2),
    ),
  ),
];

void main() {
  runAllVariants('watchlist_page', (tester, variant) async {
    await pumpAndSnapshotMobile(
      tester,
      name: 'watchlist_page',
      variant: variant,
      overrides: [
        watchlistItemsProvider.overrideWith((_) => Stream.value(_items)),
        watchlistCollectionsProvider.overrideWith(
          (_) => Stream.value(const []),
        ),
        watchlistCollectionMembersProvider.overrideWith(
          (_) => Stream.value(const []),
        ),
        watchlistQuoteSnapshotsProvider.overrideWith((_) async => _snapshots),
      ],
      child: const WatchlistPage(),
    );
  });
}
