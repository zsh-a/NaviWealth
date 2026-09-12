/// Single source of truth for the watchlist page's local view state.
///
/// Scope, sort order and the active filter live here and nowhere else: the
/// page reads them from [watchlistViewStateProvider] instead of mirroring
/// them into both SharedPreferences and the route. Only `selected` stays in
/// the URL, because it describes which row the desktop detail pane shows
/// rather than how the list itself is arranged.
///
/// These preferences affect presentation only. They never create or mutate an
/// investment portfolio and are intentionally excluded from Sync v3.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naviwealth/design_system/preferences/theme_preferences.dart';
import 'package:naviwealth/features/finance/market/domain/asset_market.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'watchlist_providers.dart';

const kWatchlistCollectionPreferenceKey =
    'naviwealth.finance.watchlist.collection';
const kWatchlistSortPreferenceKey = 'naviwealth.finance.watchlist.sort';
const kWatchlistMarketFilterPreferenceKey =
    'naviwealth.finance.watchlist.filter.market';
const kWatchlistAlertFilterPreferenceKey =
    'naviwealth.finance.watchlist.filter.alerts';
const kWatchlistFreshnessFilterPreferenceKey =
    'naviwealth.finance.watchlist.filter.freshness';

const _allScopeValue = 'all';
const _ungroupedScopeValue = 'ungrouped';
const _collectionScopePrefix = 'collection:';

/// How the watchlist list is arranged and narrowed right now.
@immutable
class WatchlistViewState {
  const WatchlistViewState({
    this.scope = const WatchlistScope.all(),
    this.sortOrder = WatchlistSortOrder.defaultOrder,
    this.filter = const WatchlistFilter(),
  });

  final WatchlistScope scope;
  final WatchlistSortOrder sortOrder;
  final WatchlistFilter filter;

  bool get hasFilter => !filter.isDefault;

  WatchlistViewState copyWith({
    WatchlistScope? scope,
    WatchlistSortOrder? sortOrder,
    WatchlistFilter? filter,
  }) => WatchlistViewState(
    scope: scope ?? this.scope,
    sortOrder: sortOrder ?? this.sortOrder,
    filter: filter ?? this.filter,
  );

  @override
  bool operator ==(Object other) =>
      other is WatchlistViewState &&
      other.scope == scope &&
      other.sortOrder == sortOrder &&
      other.filter == filter;

  @override
  int get hashCode => Object.hash(scope, sortOrder, filter);
}

final watchlistViewStateProvider =
    NotifierProvider<WatchlistViewStateController, WatchlistViewState>(
      WatchlistViewStateController.new,
    );

class WatchlistViewStateController extends Notifier<WatchlistViewState> {
  @override
  WatchlistViewState build() {
    final preferences = WatchlistViewPreferences(
      ref.watch(sharedPreferencesProvider),
    );
    ref.listen(watchlistCollectionsProvider, (_, next) {
      if (next.isLoading || next.hasError || !next.hasValue) return;
      final collectionId = state.scope.collectionId;
      if (collectionId != null &&
          !next.requireValue.any((entry) => entry.id == collectionId)) {
        unawaited(forgetScope());
      }
    });
    final initial = preferences.read();
    final collections = ref.read(watchlistCollectionsProvider);
    final collectionId = initial.scope.collectionId;
    if (collectionId != null &&
        !collections.isLoading &&
        !collections.hasError &&
        collections.hasValue &&
        !collections.requireValue.any((entry) => entry.id == collectionId)) {
      unawaited(preferences.writeScope(const WatchlistScope.all()));
      return initial.copyWith(scope: const WatchlistScope.all());
    }
    return initial;
  }

  Future<void> selectScope(WatchlistScope scope) async {
    if (scope == state.scope) return;
    state = state.copyWith(scope: scope);
    await _preferences.writeScope(scope);
  }

  Future<void> selectSortOrder(WatchlistSortOrder order) async {
    if (order == state.sortOrder) return;
    state = state.copyWith(sortOrder: order);
    await _preferences.writeSortOrder(order);
  }

  Future<void> selectFilter(WatchlistFilter filter) async {
    if (filter == state.filter) return;
    state = state.copyWith(filter: filter);
    await _preferences.writeFilter(filter);
  }

  Future<void> clearFilter() => selectFilter(const WatchlistFilter());

  /// Drops a scope whose collection no longer exists (deleted, or tombstoned
  /// by another device) so the list never renders an unreachable filter.
  Future<void> forgetScope() => selectScope(const WatchlistScope.all());

  WatchlistViewPreferences get _preferences =>
      WatchlistViewPreferences(ref.read(sharedPreferencesProvider));
}

/// SharedPreferences adapter behind [watchlistViewStateProvider]. Kept as a
/// plain class so the encoding rules stay unit-testable without Riverpod.
class WatchlistViewPreferences {
  const WatchlistViewPreferences(this._preferences);

  final SharedPreferences _preferences;

  WatchlistViewState read() => WatchlistViewState(
    scope: _readScope(),
    sortOrder: _readSortOrder(),
    filter: _readFilter(),
  );

  Future<void> writeScope(WatchlistScope scope) => _preferences.setString(
    kWatchlistCollectionPreferenceKey,
    scope.isAll
        ? _allScopeValue
        : scope.ungrouped
        ? _ungroupedScopeValue
        : '$_collectionScopePrefix${scope.collectionId}',
  );

  Future<void> writeSortOrder(WatchlistSortOrder order) =>
      _preferences.setString(kWatchlistSortPreferenceKey, switch (order) {
        WatchlistSortOrder.defaultOrder => 'default',
        WatchlistSortOrder.gainers => 'gainers',
        WatchlistSortOrder.decliners => 'decliners',
        WatchlistSortOrder.symbol => 'symbol',
      });

  Future<void> writeFilter(WatchlistFilter filter) async {
    await _writeOrClear(
      kWatchlistMarketFilterPreferenceKey,
      filter.market?.wire,
    );
    await _writeOrClear(
      kWatchlistAlertFilterPreferenceKey,
      switch (filter.alerts) {
        WatchlistAlertFilter.all => null,
        WatchlistAlertFilter.configured => 'configured',
        WatchlistAlertFilter.none => 'none',
      },
    );
    await _writeOrClear(
      kWatchlistFreshnessFilterPreferenceKey,
      switch (filter.freshness) {
        WatchlistFreshnessFilter.all => null,
        WatchlistFreshnessFilter.live => 'live',
        WatchlistFreshnessFilter.cached => 'cached',
        WatchlistFreshnessFilter.stale => 'stale',
        WatchlistFreshnessFilter.unavailable => 'unavailable',
      },
    );
  }

  WatchlistScope _readScope() {
    final value = _preferences.getString(kWatchlistCollectionPreferenceKey);
    if (value == _ungroupedScopeValue) return const WatchlistScope.ungrouped();
    if (value != null && value.startsWith(_collectionScopePrefix)) {
      final collectionId = value.substring(_collectionScopePrefix.length);
      if (collectionId.isNotEmpty) {
        return WatchlistScope.collection(collectionId);
      }
    }
    return const WatchlistScope.all();
  }

  WatchlistSortOrder _readSortOrder() =>
      switch (_preferences.getString(kWatchlistSortPreferenceKey)) {
        'gainers' => WatchlistSortOrder.gainers,
        'decliners' => WatchlistSortOrder.decliners,
        'symbol' => WatchlistSortOrder.symbol,
        _ => WatchlistSortOrder.defaultOrder,
      };

  WatchlistFilter _readFilter() {
    final market = assetMarketFromWire(
      _preferences.getString(kWatchlistMarketFilterPreferenceKey) ?? '',
    );
    return WatchlistFilter(
      market: market == AssetMarket.unknown ? null : market,
      alerts: switch (_preferences.getString(
        kWatchlistAlertFilterPreferenceKey,
      )) {
        'configured' => WatchlistAlertFilter.configured,
        'none' => WatchlistAlertFilter.none,
        _ => WatchlistAlertFilter.all,
      },
      freshness: switch (_preferences.getString(
        kWatchlistFreshnessFilterPreferenceKey,
      )) {
        'live' => WatchlistFreshnessFilter.live,
        'cached' => WatchlistFreshnessFilter.cached,
        'stale' => WatchlistFreshnessFilter.stale,
        'unavailable' => WatchlistFreshnessFilter.unavailable,
        _ => WatchlistFreshnessFilter.all,
      },
    );
  }

  Future<void> _writeOrClear(String key, String? value) => value == null
      ? _preferences.remove(key)
      : _preferences.setString(key, value);
}
