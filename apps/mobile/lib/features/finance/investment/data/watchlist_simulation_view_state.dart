import 'package:shared_preferences/shared_preferences.dart';

import 'watchlist_simulation_repository.dart';

enum WatchlistSimulationSortOrder { newest, oldest, name }

/// Device-local workspace preferences, isolated by owner and collection.
class WatchlistSimulationViewPreferences {
  const WatchlistSimulationViewPreferences(
    this._preferences, {
    required this.ownerUserId,
    required this.collectionId,
  });

  final SharedPreferences _preferences;
  final String ownerUserId;
  final String collectionId;

  String get _prefix =>
      'naviwealth.finance.watchlist.simulations/'
      '${Uri.encodeComponent(ownerUserId)}/${Uri.encodeComponent(collectionId)}/';

  String? readSelectedId() => _preferences.getString('${_prefix}selected');

  Future<void> writeSelectedId(String id) =>
      _preferences.setString('${_prefix}selected', id);

  WatchlistSimulationSortOrder readSortOrder() =>
      switch (_preferences.getString('${_prefix}sort')) {
        'oldest' => WatchlistSimulationSortOrder.oldest,
        'name' => WatchlistSimulationSortOrder.name,
        _ => WatchlistSimulationSortOrder.newest,
      };

  Future<void> writeSortOrder(WatchlistSimulationSortOrder order) =>
      _preferences.setString('${_prefix}sort', order.name);
}

List<WatchlistSimulation> arrangeWatchlistSimulations({
  required Iterable<WatchlistSimulation> simulations,
  required String query,
  required WatchlistSimulationSortOrder order,
}) {
  final normalized = query.trim().toLowerCase();
  final result = simulations
      .where((simulation) => simulation.name.toLowerCase().contains(normalized))
      .toList();
  result.sort((left, right) {
    final comparison = switch (order) {
      WatchlistSimulationSortOrder.newest => right.createdAt.compareTo(
        left.createdAt,
      ),
      WatchlistSimulationSortOrder.oldest => left.createdAt.compareTo(
        right.createdAt,
      ),
      WatchlistSimulationSortOrder.name => left.name.toLowerCase().compareTo(
        right.name.toLowerCase(),
      ),
    };
    return comparison == 0 ? left.id.compareTo(right.id) : comparison;
  });
  return result;
}
