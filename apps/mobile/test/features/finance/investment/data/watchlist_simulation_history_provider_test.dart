import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/auth/current_user.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/features/finance/data/market/market_data_providers.dart';
import 'package:naviwealth/features/finance/investment/data/watchlist_providers.dart';
import 'package:naviwealth/features/finance/investment/data/watchlist_repository.dart';
import 'package:naviwealth/features/finance/investment/data/watchlist_simulation_providers.dart';
import 'package:naviwealth/features/finance/investment/data/watchlist_simulation_repository.dart';
import 'package:naviwealth/features/finance/market/domain/asset_market.dart';
import 'package:naviwealth/features/finance/market/domain/historical_bar.dart';
import 'package:naviwealth/features/finance/market/domain/market_data_service.dart';

import '../../../../core/persistence/test_database.dart';
import '../../data/market/fake_clock.dart';
import '../../data/repositories/_stub_stamper.dart';

void main() {
  test(
    'live recorder returns the saved row and preserves skipped writes',
    () async {
      final fixture = await _Fixture.create();
      final allocation = await fixture.repository.resolveAllocation(
        ownerUserId: 'u-test',
        simulationId: fixture.simulation.id,
      );
      final recorder = fixture.container.read(
        watchlistSimulationObservationRecorderProvider,
      );
      WatchlistSimulationObservationRequest request(DateTime observedAt) =>
          WatchlistSimulationObservationRequest(
            simulation: fixture.simulation,
            observedAt: observedAt,
            weightedDailyChange: Decimal.parse('0.01'),
            pricedWeight: Decimal.one,
            missingQuoteWeight: Decimal.zero,
            allocationBasisKey: allocation.allocationBasisKey!,
          );
      final observedAt = fixture.simulation.baselineAt.add(
        const Duration(days: 1),
      );
      final saved = await recorder(request(observedAt));
      expect(saved, isNotNull);
      expect(saved!.observedAt, observedAt);
      expect(saved.projectedValue, Decimal.fromInt(1010));
      final skipped = await recorder(
        request(
          fixture.simulation.baselineAt.subtract(const Duration(days: 1)),
        ),
      );
      expect(skipped, isNull);
      expect((await fixture.observations()).last.id, saved.id);
    },
  );

  test(
    'local overview reads stored observations without fetching history',
    () async {
      final fixture = await _Fixture.create();
      final allocationSubscription = fixture.container.listen(
        watchlistSimulationAllocationProvider(fixture.simulation.id),
        (_, _) {},
      );
      addTearDown(allocationSubscription.close);
      await fixture.container.read(
        watchlistSimulationAllocationProvider(fixture.simulation.id).future,
      );
      final provider = watchlistSimulationStoredObservationsProvider(
        fixture.simulation.id,
      );
      final subscription = fixture.container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      final observations = await fixture.container.read(provider.future);
      expect(observations, hasLength(1));
      expect(fixture.market.requestCount, 0);
    },
  );

  test(
    'usable historical returns fill the completed days with coverage',
    () async {
      final fixture = await _Fixture.create();
      final result = await fixture.backfill();
      expect(result.status, WatchlistSimulationHistoryStatus.complete);
      expect(result.updatedObservationCount, 2);
      expect(result.requestedSymbolCount, 2);
      final observations = await fixture.observations();
      expect(observations, hasLength(3));
      expect(observations.last.projectedValue, Decimal.parse('1210'));
      expect(observations.last.missingQuoteWeight, Decimal.zero);
    },
  );

  test(
    'partial fetch reports failures and retry repairs incomplete days',
    () async {
      final fixture = await _Fixture.create();
      fixture.market.failedSymbols.add('MSFT');
      final result = await fixture.backfill();
      expect(result.status, WatchlistSimulationHistoryStatus.partial);
      expect(result.canRetry, isTrue);
      expect(result.failedSymbolCount, 1);
      expect(result.incompleteObservationCount, 2);
      final partial = await fixture.observations();
      expect(partial.last.missingQuoteWeight, Decimal.parse('0.5'));
      expect(partial.last.projectedValue, Decimal.parse('1102.5'));

      fixture.market.failedSymbols.clear();
      fixture.container.invalidate(fixture.provider);
      final repaired = await fixture.container.read(fixture.provider.future);
      expect(repaired.status, WatchlistSimulationHistoryStatus.complete);
      expect(repaired.updatedObservationCount, 2);
      final complete = await fixture.observations();
      expect(
        complete.map((observation) => observation.id),
        partial.map((observation) => observation.id),
      );
      expect(complete.last.missingQuoteWeight, Decimal.zero);
      expect(complete.last.projectedValue, Decimal.parse('1210'));

      // A later failure cannot downgrade complete days or their value chain.
      fixture.market.failedSymbols.add('MSFT');
      fixture.container.invalidate(fixture.provider);
      final degraded = await fixture.container.read(fixture.provider.future);
      expect(degraded.updatedObservationCount, 0);
      expect(
        (await fixture.observations()).last.projectedValue,
        Decimal.parse('1210'),
      );
    },
  );

  test(
    'all request failures remain distinguishable from empty history',
    () async {
      final fixture = await _Fixture.create();
      fixture.market.failedSymbols.addAll(['AAPL', 'MSFT']);
      final result = await fixture.backfill();
      expect(result.status, WatchlistSimulationHistoryStatus.failed);
      expect(result.failedSymbolCount, 2);
      expect(result.canRetry, isTrue);
      expect(await fixture.observations(), hasLength(1));
    },
  );

  test(
    'repair cannot replace an observation from an earlier allocation',
    () async {
      final fixture = await _Fixture.create();
      final original = await fixture.repository.resolveAllocation(
        ownerUserId: 'u-test',
        simulationId: fixture.simulation.id,
      );
      final observedAt = fixture.simulation.baselineAt.add(
        const Duration(days: 1),
      );
      await fixture.repository.recordObservation(
        simulation: fixture.simulation,
        observedAt: observedAt,
        weightedDailyChange: Decimal.parse('0.05'),
        pricedWeight: Decimal.parse('0.5'),
        missingQuoteWeight: Decimal.parse('0.5'),
        allocationBasisKey: original.allocationBasisKey!,
      );
      await fixture.repository.replaceAllocation(
        simulation: fixture.simulation,
        targetWeights: {
          'us_stock:AAPL': Decimal.parse('0.25'),
          'us_stock:MSFT': Decimal.parse('0.75'),
        },
        cashWeight: Decimal.zero,
      );
      final current = await fixture.repository.resolveAllocation(
        ownerUserId: 'u-test',
        simulationId: fixture.simulation.id,
      );
      expect(current.allocationBasisKey, isNot(original.allocationBasisKey));
      final changed = await fixture.repository.mergeObservationInputs(
        simulation: fixture.simulation,
        allocationBasisKey: current.allocationBasisKey!,
        repairIncompleteObservations: true,
        inputs: [
          WatchlistSimulationObservationInput(
            observedAt: observedAt,
            weightedDailyChange: Decimal.parse('0.2'),
            pricedWeight: Decimal.one,
            missingQuoteWeight: Decimal.zero,
          ),
        ],
      );
      expect(changed, 0);
      final observations = await fixture.observations();
      expect(observations.last.allocationBasisKey, original.allocationBasisKey);
      expect(observations.last.projectedValue, Decimal.parse('1050'));
      expect(observations.last.missingQuoteWeight, Decimal.parse('0.5'));
    },
  );

  test('empty historical responses report no data', () async {
    final fixture = await _Fixture.create();
    fixture.market.empty = true;
    final result = await fixture.backfill();
    expect(result.status, WatchlistSimulationHistoryStatus.noData);
    expect(result.unavailableSymbolCount, 2);
    expect(await fixture.observations(), hasLength(1));
  });

  test('stale historical cache never creates fresh observations', () async {
    final fixture = await _Fixture.create();
    fixture.market.freshness = DataFreshness.stale;
    final result = await fixture.backfill();
    expect(result.status, WatchlistSimulationHistoryStatus.partial);
    expect(result.staleSymbolCount, 2);
    expect(result.updatedObservationCount, 0);
    expect(await fixture.observations(), hasLength(1));
  });

  test('a new baseline needs no historical requests', () async {
    final fixture = await _Fixture.create(daysSinceBaseline: 1);
    final result = await fixture.backfill();
    expect(result.status, WatchlistSimulationHistoryStatus.notNeeded);
    expect(fixture.market.requestCount, 0);
  });
}

class _Fixture {
  _Fixture(
    this.db,
    this.repository,
    this.simulation,
    this.market,
    this.container,
  );

  final AppDatabase db;
  final WatchlistSimulationRepository repository;
  final WatchlistSimulation simulation;
  final _Market market;
  final ProviderContainer container;
  late final provider = watchlistSimulationHistoricalBackfillProvider(
    simulation.id,
  );

  static Future<_Fixture> create({int daysSinceBaseline = 4}) async {
    final db = makeTestDatabase();
    final repository = WatchlistSimulationRepository(
      db: db,
      outbox: InMemoryOutboxStore(),
      stamper: makeStubStamper(),
    );
    final simulation = await repository.create(
      collectionId: 'collection-test',
      name: 'History fixture',
      baseCurrency: 'USD',
      startingCapital: Decimal.parse('1000'),
      targetWeights: {
        'us_stock:AAPL': Decimal.parse('0.5'),
        'us_stock:MSFT': Decimal.parse('0.5'),
      },
      cashWeight: Decimal.zero,
    );
    final baseline = simulation.baselineAt.toUtc();
    final baselineDay = DateTime.utc(
      baseline.year,
      baseline.month,
      baseline.day,
    );
    final market = _Market(baselineDay);
    final container = ProviderContainer(
      overrides: [
        currentUserIdProvider.overrideWith(
          (_) =>
              () async => 'u-test',
        ),
        watchlistSimulationRepositoryProvider.overrideWith(
          (_) async => repository,
        ),
        watchlistSimulationsProvider.overrideWith(
          (_) => Stream.value([simulation]),
        ),
        watchlistItemsProvider.overrideWith(
          (_) => Stream.value([
            for (final symbol in ['AAPL', 'MSFT'])
              WatchlistItem(
                id: 'us_stock:$symbol',
                symbol: symbol,
                market: AssetMarket.usStock,
                addedAt: baseline,
                alertRules: const PriceAlertRules(),
                sync: simulation.sync,
              ),
          ]),
        ),
        marketDataServiceProvider.overrideWith((_) async => market),
        clockProvider.overrideWithValue(
          FakeClock(baselineDay.add(Duration(days: daysSinceBaseline))),
        ),
      ],
    );
    final fixture = _Fixture(db, repository, simulation, market, container);
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    return fixture;
  }

  Future<WatchlistSimulationHistoryResult> backfill() {
    final subscription = container.listen(provider, (_, _) {});
    addTearDown(subscription.close);
    return container.read(provider.future);
  }

  Future<List<WatchlistSimulationObservation>> observations() => repository
      .watchObservations(ownerUserId: 'u-test', simulationId: simulation.id)
      .first;
}

class _Market implements MarketDataService {
  _Market(this.baseline);
  final DateTime baseline;
  final failedSymbols = <String>{};
  var requestCount = 0;
  var empty = false;
  var freshness = DataFreshness.live;

  @override
  Future<MarketResponse<List<HistoricalBar>>> getHistorical(
    String symbol, {
    required DateTime from,
    required DateTime to,
    BarInterval interval = BarInterval.day,
    AssetMarket? market,
  }) async {
    requestCount++;
    if (failedSymbols.contains(symbol)) throw StateError('Fixture unavailable');
    return MarketResponse(
      data: empty
          ? []
          : [
              for (var day = 0; day < 3; day++)
                HistoricalBar(
                  symbol: symbol,
                  asOf: baseline.add(Duration(days: day)),
                  open: Decimal.fromInt([100, 110, 121][day]),
                  high: Decimal.fromInt([100, 110, 121][day]),
                  low: Decimal.fromInt([100, 110, 121][day]),
                  close: Decimal.fromInt([100, 110, 121][day]),
                ),
            ],
      freshness: freshness,
      source: 'fixture',
      fetchedAt: baseline.add(const Duration(days: 4)),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
