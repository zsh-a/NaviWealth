import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/investment/data/watchlist_providers.dart';
import 'package:naviwealth/features/finance/investment/data/watchlist_view_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('defaults to all symbols and manual ordering', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final preferences = WatchlistViewPreferences(
      await SharedPreferences.getInstance(),
    );

    expect(preferences.scope.isAll, isTrue);
    expect(preferences.sortOrder, WatchlistSortOrder.defaultOrder);
  });

  test('persists collection scope and sort order explicitly', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final sharedPreferences = await SharedPreferences.getInstance();
    final preferences = WatchlistViewPreferences(sharedPreferences);

    await preferences.setScope(const WatchlistScope.collection('growth'));
    await preferences.setSortOrder(WatchlistSortOrder.decliners);

    expect(preferences.scope.collectionId, 'growth');
    expect(preferences.sortOrder, WatchlistSortOrder.decliners);
    expect(
      sharedPreferences.getString(kWatchlistCollectionPreferenceKey),
      'collection:growth',
    );
    expect(
      sharedPreferences.getString(kWatchlistSortPreferenceKey),
      'decliners',
    );

    await preferences.setScope(const WatchlistScope.ungrouped());
    await preferences.setSortOrder(WatchlistSortOrder.defaultOrder);
    expect(preferences.scope.ungrouped, isTrue);
    expect(preferences.sortOrder, WatchlistSortOrder.defaultOrder);

    await preferences.setScope(const WatchlistScope.all());
    expect(preferences.scope.isAll, isTrue);
    expect(
      sharedPreferences.getString(kWatchlistCollectionPreferenceKey),
      'all',
    );
  });

  test('ignores malformed persisted values', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      kWatchlistCollectionPreferenceKey: 'collection:',
      kWatchlistSortPreferenceKey: 'unexpected',
    });
    final preferences = WatchlistViewPreferences(
      await SharedPreferences.getInstance(),
    );

    expect(preferences.scope.isAll, isTrue);
    expect(preferences.sortOrder, WatchlistSortOrder.defaultOrder);
  });
}
