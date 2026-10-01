import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/finance/composition/finance_route_paths.dart';
import 'package:naviwealth/features/finance/investment/data/watchlist_simulation_repository.dart';
import 'package:naviwealth/features/finance/investment/data/watchlist_simulation_view_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'workspace defaults and selection survive rebuilding the adapter',
    () async {
      SharedPreferences.setMockInitialValues({});
      final shared = await SharedPreferences.getInstance();
      WatchlistSimulationViewPreferences adapter() =>
          WatchlistSimulationViewPreferences(
            shared,
            ownerUserId: 'owner',
            collectionId: 'growth',
          );
      expect(adapter().readSelectedId(), isNull);
      expect(adapter().readSortOrder(), WatchlistSimulationSortOrder.newest);
      await adapter().writeSelectedId('simulation-two');
      await adapter().writeSortOrder(WatchlistSimulationSortOrder.name);
      expect(adapter().readSelectedId(), 'simulation-two');
      expect(adapter().readSortOrder(), WatchlistSimulationSortOrder.name);
    },
  );

  test('selection and sort are isolated by owner and collection, including separators', () async {
    SharedPreferences.setMockInitialValues({});
    final shared = await SharedPreferences.getInstance();
    WatchlistSimulationViewPreferences adapter(
      String owner,
      String collection,
    ) => WatchlistSimulationViewPreferences(
      shared,
      ownerUserId: owner,
      collectionId: collection,
    );
    await adapter('a/b', 'c').writeSelectedId('first');
    await adapter('a', 'b/c').writeSelectedId('second');
    await adapter('a', 'c').writeSortOrder(WatchlistSimulationSortOrder.oldest);
    expect(adapter('a/b', 'c').readSelectedId(), 'first');
    expect(adapter('a', 'b/c').readSelectedId(), 'second');
    expect(adapter('a', 'c').readSelectedId(), isNull);
    expect(
      adapter('a/b', 'c').readSortOrder(),
      WatchlistSimulationSortOrder.newest,
    );
  });

  test(
    'search trims whitespace and matches Chinese or case-insensitive names',
    () {
      final scenarios = [_simulation('a', 'Growth'), _simulation('b', '稳健收入')];
      expect(
        arrangeWatchlistSimulations(
          simulations: scenarios,
          query: ' gRoW ',
          order: WatchlistSimulationSortOrder.name,
        ).map((item) => item.id),
        ['a'],
      );
      expect(
        arrangeWatchlistSimulations(
          simulations: scenarios,
          query: '收入',
          order: WatchlistSimulationSortOrder.name,
        ).map((item) => item.id),
        ['b'],
      );
      expect(
        arrangeWatchlistSimulations(
          simulations: scenarios,
          query: 'missing',
          order: WatchlistSimulationSortOrder.name,
        ),
        isEmpty,
      );
      expect(scenarios.map((item) => item.id), ['a', 'b']);
    },
  );

  test(
    'creation ordering and name ordering are stable across stream order',
    () {
      final a = _simulation('a', 'Zoo');
      final b = _simulation('b', 'Apple', day: 2);
      final c = _simulation('c', 'apple', day: 2);
      List<String> sorted(WatchlistSimulationSortOrder order) =>
          arrangeWatchlistSimulations(
            simulations: [c, a, b],
            query: '',
            order: order,
          ).map((item) => item.id).toList();
      expect(sorted(WatchlistSimulationSortOrder.newest), ['b', 'c', 'a']);
      expect(sorted(WatchlistSimulationSortOrder.oldest), ['a', 'b', 'c']);
      expect(sorted(WatchlistSimulationSortOrder.name), ['b', 'c', 'a']);
    },
  );

  test('scenario links preserve the collection route and encode ids', () {
    const collection = '收藏 / income';
    const simulation = 'mix/a?b&c=#';
    final uri = Uri.parse(
      FinanceRoutes.wealthWatchlistSimulationsFor(
        collection,
        simulationId: simulation,
      ),
    );
    expect(uri.pathSegments, [
      'wealth',
      'watchlist',
      'collections',
      collection,
      'simulations',
    ]);
    expect(uri.queryParameters['simulationId'], simulation);
    expect(
      FinanceRoutes.wealthWatchlistSimulationsFor('growth'),
      '/wealth/watchlist/collections/growth/simulations',
    );
  });
}

WatchlistSimulation _simulation(String id, String name, {int day = 1}) =>
    WatchlistSimulation(
      id: id,
      collectionId: 'collection',
      name: name,
      baseCurrency: 'USD',
      startingCapital: Decimal.fromInt(1000),
      cashWeight: Decimal.one,
      baselineAt: DateTime.utc(2026, 10, day),
      createdAt: DateTime.utc(2026, 10, day),
      sync: SyncMeta(
        ownerUserId: 'owner',
        updatedAt: DateTime.utc(2026, 10, day),
        updatedByDevice: 'test',
        hlc: Hlc.zero('test'),
      ),
    );
