import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/design_system/preferences/theme_preferences.dart';
import 'package:naviwealth/features/finance/investment/data/watchlist_providers.dart';
import 'package:naviwealth/features/finance/investment/data/watchlist_repository.dart';
import 'package:naviwealth/features/finance/investment/data/watchlist_view_state.dart';
import 'package:naviwealth/features/finance/market/domain/asset_market.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('resets a remotely deleted collection in the controller, preserving sort and filter', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final collections = StreamController<List<WatchlistCollection>>();
    addTearDown(collections.close);
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        watchlistCollectionsProvider.overrideWith((_) => collections.stream),
      ],
    );
    addTearDown(container.dispose);
    container.listen(watchlistViewStateProvider, (_, _) {});
    final controller = container.read(watchlistViewStateProvider.notifier);
    collections.add([
      WatchlistCollection(
        id: 'growth',
        name: 'Growth',
        createdAt: DateTime.utc(2026),
        sync: SyncMeta(
          ownerUserId: 'u',
          updatedAt: DateTime.utc(2026),
          updatedByDevice: 'test',
          hlc: Hlc.zero('test'),
        ),
      ),
    ]);
    await container.pump();
    await controller.selectScope(const WatchlistScope.collection('growth'));
    await controller.selectSortOrder(WatchlistSortOrder.decliners);
    await controller.selectFilter(
      const WatchlistFilter(market: AssetMarket.hkStock),
    );
    collections.add(const []);
    await container.pump();
    final state = container.read(watchlistViewStateProvider);
    expect(state.scope.isAll, isTrue);
    expect(state.sortOrder, WatchlistSortOrder.decliners);
    expect(state.filter.market, AssetMarket.hkStock);
    expect(preferences.getString(kWatchlistCollectionPreferenceKey), 'all');
  });

  test('defaults to all symbols, manual ordering, no filter', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final preferences = WatchlistViewPreferences(
      await SharedPreferences.getInstance(),
    );

    final state = preferences.read();
    expect(state.scope.isAll, isTrue);
    expect(state.sortOrder, WatchlistSortOrder.defaultOrder);
    expect(state.filter.isDefault, isTrue);
    expect(state.hasFilter, isFalse);
  });

  test('round-trips scope, sort order and filter through storage', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final sharedPreferences = await SharedPreferences.getInstance();
    final preferences = WatchlistViewPreferences(sharedPreferences);

    await preferences.writeScope(const WatchlistScope.collection('growth'));
    await preferences.writeSortOrder(WatchlistSortOrder.decliners);
    await preferences.writeFilter(
      const WatchlistFilter(
        market: AssetMarket.usStock,
        alerts: WatchlistAlertFilter.configured,
        freshness: WatchlistFreshnessFilter.stale,
      ),
    );

    expect(
      sharedPreferences.getString(kWatchlistCollectionPreferenceKey),
      'collection:growth',
    );
    expect(
      sharedPreferences.getString(kWatchlistSortPreferenceKey),
      'decliners',
    );
    expect(
      sharedPreferences.getString(kWatchlistMarketFilterPreferenceKey),
      AssetMarket.usStock.wire,
    );

    final state = preferences.read();
    expect(state.scope.collectionId, 'growth');
    expect(state.sortOrder, WatchlistSortOrder.decliners);
    expect(state.filter.market, AssetMarket.usStock);
    expect(state.filter.alerts, WatchlistAlertFilter.configured);
    expect(state.filter.freshness, WatchlistFreshnessFilter.stale);
    expect(state.filter.activeCount, 3);
  });

  test(
    'clearing the filter removes its keys instead of blanking them',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final sharedPreferences = await SharedPreferences.getInstance();
      final preferences = WatchlistViewPreferences(sharedPreferences);

      await preferences.writeFilter(
        const WatchlistFilter(market: AssetMarket.hkStock),
      );
      await preferences.writeFilter(const WatchlistFilter());

      expect(
        sharedPreferences.getString(kWatchlistMarketFilterPreferenceKey),
        isNull,
      );
      expect(
        sharedPreferences.getString(kWatchlistAlertFilterPreferenceKey),
        isNull,
      );
      expect(
        sharedPreferences.getString(kWatchlistFreshnessFilterPreferenceKey),
        isNull,
      );
      expect(preferences.read().filter.isDefault, isTrue);
    },
  );

  test('writes the ungrouped and all scopes distinctly', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final sharedPreferences = await SharedPreferences.getInstance();
    final preferences = WatchlistViewPreferences(sharedPreferences);

    await preferences.writeScope(const WatchlistScope.ungrouped());
    expect(
      sharedPreferences.getString(kWatchlistCollectionPreferenceKey),
      'ungrouped',
    );
    expect(preferences.read().scope.ungrouped, isTrue);

    await preferences.writeScope(const WatchlistScope.all());
    expect(
      sharedPreferences.getString(kWatchlistCollectionPreferenceKey),
      'all',
    );
    expect(preferences.read().scope.isAll, isTrue);
  });

  test('ignores malformed persisted values', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      kWatchlistCollectionPreferenceKey: 'collection:',
      kWatchlistSortPreferenceKey: 'unexpected',
      kWatchlistMarketFilterPreferenceKey: 'not-a-market',
      kWatchlistAlertFilterPreferenceKey: 'not-a-filter',
      kWatchlistFreshnessFilterPreferenceKey: 'not-a-freshness',
    });
    final preferences = WatchlistViewPreferences(
      await SharedPreferences.getInstance(),
    );

    final state = preferences.read();
    expect(state.scope.isAll, isTrue);
    expect(state.sortOrder, WatchlistSortOrder.defaultOrder);
    expect(state.filter.isDefault, isTrue);
  });
}
