import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/investment/data/watchlist_providers.dart';
import 'package:naviwealth/features/finance/investment/data/watchlist_repository.dart';
import 'package:naviwealth/features/finance/investment/data/watchlist_simulation_providers.dart';
import 'package:naviwealth/features/finance/investment/data/watchlist_simulation_repository.dart';
import 'package:naviwealth/features/finance/investment/ui/watchlist_simulation_section.dart';
import 'package:naviwealth/features/finance/market/domain/asset_market.dart';
import 'package:naviwealth/features/finance/market/domain/market_data_service.dart';
import 'package:naviwealth/features/finance/market/domain/quote.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '_golden_setup.dart';

final _sync = SyncMeta(
  ownerUserId: 'u-golden',
  updatedAt: DateTime.utc(2026, 8, 31),
  updatedByDevice: 'golden',
  hlc: Hlc.zero('golden'),
);

final _collection = WatchlistCollection(
  id: 'collection-growth',
  name: 'Growth',
  createdAt: DateTime.utc(2026, 8, 31),
  sync: _sync,
);

final _items = [
  WatchlistItem(
    id: 'us_stock:AAPL',
    symbol: 'AAPL',
    market: AssetMarket.usStock,
    addedAt: DateTime.utc(2026, 8, 31),
    alertRules: const PriceAlertRules(),
    sync: _sync,
    nameEn: 'Apple Inc.',
    nameCn: '苹果公司',
  ),
  WatchlistItem(
    id: 'us_stock:MSFT',
    symbol: 'MSFT',
    market: AssetMarket.usStock,
    addedAt: DateTime.utc(2026, 8, 31),
    alertRules: const PriceAlertRules(),
    sync: _sync,
    nameEn: 'Microsoft',
    nameCn: '微软',
  ),
];

final _simulation = WatchlistSimulation(
  id: 'simulation-growth',
  collectionId: _collection.id,
  name: 'Growth paper mix',
  baseCurrency: 'USD',
  startingCapital: Decimal.parse('100000'),
  cashWeight: Decimal.parse('0.1'),
  baselineAt: DateTime.utc(2026, 8, 31),
  createdAt: DateTime.utc(2026, 8, 31),
  sync: _sync,
);

final _positions = [
  WatchlistSimulationPosition(
    id: 'position-aapl',
    simulationId: _simulation.id,
    watchlistItemId: _items[0].id,
    targetWeight: Decimal.parse('0.6'),
    createdAt: DateTime.utc(2026, 8, 31),
    sync: _sync,
  ),
  WatchlistSimulationPosition(
    id: 'position-msft',
    simulationId: _simulation.id,
    watchlistItemId: _items[1].id,
    targetWeight: Decimal.parse('0.3'),
    createdAt: DateTime.utc(2026, 8, 31),
    sync: _sync,
  ),
];

final _snapshots = [
  WatchlistQuoteSnapshot(
    item: _items[0],
    response: MarketResponse(
      data: Quote(
        symbol: 'AAPL',
        currency: 'USD',
        price: Decimal.parse('201'),
        previousClose: Decimal.parse('200'),
        asOf: DateTime.utc(2026, 8, 31, 2),
      ),
      freshness: DataFreshness.cachedFresh,
      source: 'golden',
      fetchedAt: DateTime.utc(2026, 8, 31, 2),
    ),
  ),
];

final _observations = [
  WatchlistSimulationObservation(
    id: 'observation-baseline',
    simulationId: _simulation.id,
    observationDay: '2026-08-31',
    observedAt: DateTime.utc(2026, 8, 31),
    projectedValue: Decimal.parse('100000'),
    weightedDailyChange: Decimal.zero,
    pricedWeight: Decimal.zero,
    missingQuoteWeight: Decimal.parse('0.9'),
  ),
  WatchlistSimulationObservation(
    id: 'observation-next-day',
    simulationId: _simulation.id,
    observationDay: '2026-09-01',
    observedAt: DateTime.utc(2026, 9),
    projectedValue: Decimal.parse('100300'),
    weightedDailyChange: Decimal.parse('0.003'),
    pricedWeight: Decimal.parse('0.6'),
    missingQuoteWeight: Decimal.parse('0.3'),
  ),
];

void main() {
  runAllVariants('watchlist_simulation_section', (tester, variant) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final preferences = await SharedPreferences.getInstance();
    await pumpAndSnapshotMobile(
      tester,
      name: 'watchlist_simulation_section',
      variant: variant,
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        watchlistSimulationsProvider.overrideWith(
          (_) => Stream.value([_simulation]),
        ),
        watchlistSimulationPositionsProvider.overrideWith(
          (_, _) => Stream.value(_positions),
        ),
        watchlistSimulationObservationsProvider.overrideWith(
          (_, _) => Stream.value(_observations),
        ),
        watchlistSimulationActionEntriesProvider.overrideWith(
          (_, _) => Stream.value(const []),
        ),
        watchlistSimulationActionReconciliationProvider.overrideWith(
          (_, _) async => const WatchlistSimulationActionReconciliation(
            materializedCount: 0,
            failedSymbolCount: 0,
            unsupportedSymbolCount: 0,
          ),
        ),
        watchlistSimulationObservationRecorderProvider.overrideWithValue(
          (_) async {},
        ),
      ],
      child: Scaffold(
        body: ListView(
          padding: const EdgeInsets.all(AppSpacing.s12),
          children: [
            WatchlistSimulationSection(
              collection: _collection,
              items: _items,
              snapshots: _snapshots,
            ),
          ],
        ),
      ),
    );
  });
}
