import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/investment/data/watchlist_providers.dart';
import 'package:naviwealth/features/finance/investment/data/watchlist_repository.dart';
import 'package:naviwealth/features/finance/investment/ui/watchlist_page.dart';
import 'package:naviwealth/features/finance/investment/ui/watchlist_rows.dart';
import 'package:naviwealth/features/finance/market/domain/asset_market.dart';
import 'package:naviwealth/features/finance/market/domain/historical_bar.dart';
import 'package:naviwealth/features/finance/market/domain/market_data_service.dart';
import 'package:naviwealth/features/finance/market/domain/quote.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    nameEn: 'Apple Inc.',
    nameCn: '苹果公司',
  ),
  WatchlistItem(
    id: 'hk_stock:2800.HK',
    symbol: '2800.HK',
    market: AssetMarket.hkStock,
    addedAt: DateTime.utc(2026, 5, 18, 1),
    alertRules: PriceAlertRules(below: _d('18')),
    sync: _meta(),
    nameEn: 'Tracker Fund of Hong Kong',
    nameCn: '盈富基金',
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
        open: _d('200.50'),
        dayHigh: _d('202.30'),
        dayLow: _d('198.20'),
        volume: 42000000,
        exchange: 'NASDAQ',
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
  runAllVariants('watchlist_symbol_detail', (tester, variant) async {
    await pumpAndSnapshotMobile(
      tester,
      name: 'watchlist_symbol_detail',
      variant: variant,
      overrides: [
        watchlistHistoryProvider.overrideWith(
          (_, key) async => [
            for (var i = 0; i < 15; i++)
              HistoricalBar(
                symbol: key.symbol,
                asOf: DateTime.utc(2026, 5, 4 + i),
                open: _d('190'),
                high: _d('202'),
                low: _d('188'),
                close: Decimal.fromInt(190 + i - (i % 3)),
              ),
          ],
        ),
      ],
      child: ObjectDetailScaffold(
        title: 'AAPL details',
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.s16),
          child: WatchlistSymbolView(
            item: _items.first,
            snapshot: _snapshots.first,
            loadingQuote: false,
            onEdit: () {},
            onManageCollections: () {},
            onRemoveFromCollection: null,
            onRemove: () {},
          ),
        ),
      ),
    );
  });

  runAllVariants('watchlist_page', (tester, variant) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final preferences = await SharedPreferences.getInstance();
    await pumpAndSnapshotMobile(
      tester,
      name: 'watchlist_page',
      variant: variant,
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        watchlistItemsProvider.overrideWith((_) => Stream.value(_items)),
        watchlistCollectionsProvider.overrideWith(
          (_) => Stream.value(const []),
        ),
        watchlistCollectionMembersProvider.overrideWith(
          (_) => Stream.value(const []),
        ),
        watchlistQuoteUpdatesProvider.overrideWith(
          (_, _) => Stream.value(_snapshots),
        ),
        watchlistQuoteSnapshotsProvider.overrideWith((_) async => _snapshots),
        watchlistSparklineProvider.overrideWith(
          (_, key) async => key.symbol == 'AAPL'
              ? [192.5, 194, 193.25, 197, 198.5, 196.75, 201.25]
              : [19.4, 19.2, 19.1, 18.9, 19.05, 18.6, 18.42],
        ),
      ],
      child: const WatchlistPage(),
    );
  });
}
