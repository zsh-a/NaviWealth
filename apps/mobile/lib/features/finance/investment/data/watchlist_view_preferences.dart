import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naviwealth/design_system/preferences/theme_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'watchlist_providers.dart';

const kWatchlistCollectionPreferenceKey =
    'naviwealth.finance.watchlist.collection';
const kWatchlistSortPreferenceKey = 'naviwealth.finance.watchlist.sort';

const _allScopeValue = 'all';
const _ungroupedScopeValue = 'ungrouped';
const _collectionScopePrefix = 'collection:';

final watchlistViewPreferencesProvider = Provider<WatchlistViewPreferences>(
  (ref) => WatchlistViewPreferences(ref.watch(sharedPreferencesProvider)),
);

/// Local-only view state for the watchlist page.
///
/// These preferences affect presentation only. They never create or mutate an
/// investment portfolio and are intentionally excluded from Sync v3.
class WatchlistViewPreferences {
  const WatchlistViewPreferences(this._preferences);

  final SharedPreferences _preferences;

  WatchlistScope get scope {
    final value = _preferences.getString(kWatchlistCollectionPreferenceKey);
    if (value == _ungroupedScopeValue) {
      return const WatchlistScope.ungrouped();
    }
    if (value != null && value.startsWith(_collectionScopePrefix)) {
      final collectionId = value.substring(_collectionScopePrefix.length);
      if (collectionId.isNotEmpty) {
        return WatchlistScope.collection(collectionId);
      }
    }
    return const WatchlistScope.all();
  }

  WatchlistSortOrder get sortOrder {
    return switch (_preferences.getString(kWatchlistSortPreferenceKey)) {
      'gainers' => WatchlistSortOrder.gainers,
      'decliners' => WatchlistSortOrder.decliners,
      'symbol' => WatchlistSortOrder.symbol,
      _ => WatchlistSortOrder.defaultOrder,
    };
  }

  Future<void> setScope(WatchlistScope scope) async {
    final value = scope.isAll
        ? _allScopeValue
        : scope.ungrouped
        ? _ungroupedScopeValue
        : '$_collectionScopePrefix${scope.collectionId}';
    await _preferences.setString(kWatchlistCollectionPreferenceKey, value);
  }

  Future<void> setSortOrder(WatchlistSortOrder order) async {
    final value = switch (order) {
      WatchlistSortOrder.defaultOrder => 'default',
      WatchlistSortOrder.gainers => 'gainers',
      WatchlistSortOrder.decliners => 'decliners',
      WatchlistSortOrder.symbol => 'symbol',
    };
    await _preferences.setString(kWatchlistSortPreferenceKey, value);
  }
}
