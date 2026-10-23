import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/features/finance/investment/data/watchlist_simulation_repository.dart';
import 'package:naviwealth/features/finance/market/domain/asset_market.dart';

import '../../../../core/persistence/test_database.dart';
import '../../data/repositories/_stub_stamper.dart';

class _SnapshotProbe extends QueryInterceptor {
  bool enabled = false;
  int returnedRows = 0;
  final executors = <QueryExecutor>[];

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final rows = await executor.runSelect(statement, args);
    if (enabled) {
      returnedRows += rows.length;
      executors.add(executor);
    }
    return rows;
  }
}

void main() {
  test('snapshot reads current holdings once and only its predecessor headers', () async {
    // This fixture intercepts the real SQLite executor to assert that a long
    // history cannot cause a multiplicative result set or non-atomic reads.
    final probe = _SnapshotProbe();
    final db = AppDatabase(
      DatabaseConnection(NativeDatabase.memory().interceptWith(probe)),
    );
    addTearDown(db.close);
    final repository = WatchlistSimulationRepository(
      db: db,
      outbox: InMemoryOutboxStore(),
      stamper: makeStubStamper(),
    );
    Map<String, Decimal> weights(String weight) => {
      for (var i = 0; i < 20; i++) 'us_stock:ITEM$i': Decimal.parse(weight),
    };
    final simulation = await repository.create(
      collectionId: 'scale',
      name: 'Long history',
      baseCurrency: 'USD',
      startingCapital: Decimal.fromInt(1000),
      targetWeights: weights('0.05'),
      cashWeight: Decimal.zero,
    );
    for (var i = 0; i < 30; i++) {
      await repository.replaceAllocation(
        simulation: simulation,
        targetWeights: weights(i.isEven ? '0.04' : '0.03'),
        cashWeight: Decimal.parse(i.isEven ? '0.2' : '0.4'),
      );
    }
    final template = await (db.select(
      db.watchlistSimulationAllocationVersions,
    )..limit(1)).getSingle();
    for (var i = 0; i < 40; i++) {
      await db
          .into(db.watchlistSimulationAllocationVersions)
          .insert(
            template.copyWith(
              id: 'unselected-$i',
              previousAllocationVersionId: const Value(null),
            ),
          );
    }
    probe.enabled = true;
    final selected = await repository.resolveAllocation(
      ownerUserId: 'u-test',
      simulationId: simulation.id,
    );
    probe.enabled = false;
    expect(selected.positions, hasLength(20));
    expect(selected.validAllocationBasisKeys, hasLength(31));
    // 31 selected-lineage headers + 20 current holdings + definition and head.
    expect(probe.returnedRows, lessThanOrEqualTo(53));
    expect(probe.executors, isNotEmpty);
    expect(
      probe.executors.every((executor) => executor is TransactionExecutor),
      isTrue,
    );
    expect(probe.executors.toSet(), hasLength(1));
  });

  test(
    'watch emits only committed snapshots while head and children change',
    () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final repository = WatchlistSimulationRepository(
        db: db,
        outbox: InMemoryOutboxStore(),
        stamper: makeStubStamper(),
      );
      final simulation = await repository.create(
        collectionId: 'growth',
        name: 'Atomic watch',
        baseCurrency: 'USD',
        startingCapital: Decimal.fromInt(1000),
        targetWeights: {'us_stock:AAPL': Decimal.one},
        cashWeight: Decimal.zero,
      );
      final events = <ResolvedWatchlistSimulationAllocation>[];
      final initial = Completer<void>();
      final changed = Completer<void>();
      final subscription = repository
          .watchResolvedAllocation(
            ownerUserId: 'u-test',
            simulationId: simulation.id,
          )
          .listen((allocation) {
            events.add(allocation);
            if (!initial.isCompleted) initial.complete();
            if (allocation.positions.any(
                  (p) => p.watchlistItemId == 'us_stock:MSFT',
                ) &&
                !changed.isCompleted) {
              changed.complete();
            }
          });
      addTearDown(subscription.cancel);
      await initial.future.timeout(const Duration(seconds: 5));
      await repository.replaceAllocation(
        simulation: simulation,
        targetWeights: {'us_stock:MSFT': Decimal.parse('0.6')},
        cashWeight: Decimal.parse('0.4'),
      );
      await changed.future.timeout(const Duration(seconds: 5));
      expect(events.every((e) => e.isUsable), isTrue);
      expect(events.every((e) => e.positions.length == 1), isTrue);
      expect(events.last.cashWeight, Decimal.parse('0.4'));
    },
  );

  test('quantity coverage is separate from complete weight and all-cash allocations', () async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final repository = WatchlistSimulationRepository(
      db: db,
      outbox: InMemoryOutboxStore(),
      stamper: makeStubStamper(),
    );
    final simulation = await repository.create(
      collectionId: 'growth',
      name: 'Partial quote evidence',
      baseCurrency: 'USD',
      startingCapital: Decimal.fromInt(1000),
      targetWeights: {
        'us_stock:AAPL': Decimal.parse('0.5'),
        'us_stock:MSFT': Decimal.parse('0.5'),
      },
      cashWeight: Decimal.zero,
      holdingInputs: {
        'us_stock:AAPL': WatchlistSimulationHoldingInput(
          symbol: 'AAPL',
          market: AssetMarket.usStock,
          rawPrice: Decimal.fromInt(100),
          priceCurrency: 'USD',
          priceAsOf: DateTime.utc(2023, 11, 14),
          priceSource: 'fixture',
        ),
      },
    );
    final allocation = await repository.resolveAllocation(
      ownerUserId: 'u-test',
      simulationId: simulation.id,
    );
    expect(allocation.isUsable, isTrue);
    expect(
      allocation.quantityCoverage,
      WatchlistSimulationQuantityCoverage.partial,
    );
    expect(allocation.positions.first.quantity, Decimal.fromInt(5));
    expect(allocation.positions.last.quantity, isNull);
    await repository.replaceAllocation(
      simulation: simulation,
      targetWeights: const {},
      cashWeight: Decimal.one,
    );
    final cash = await repository.resolveAllocation(
      ownerUserId: 'u-test',
      simulationId: simulation.id,
    );
    expect(cash.isUsable, isTrue);
    expect(cash.quantityCoverage, WatchlistSimulationQuantityCoverage.complete);
    expect(cash.positions, isEmpty);
  });
}
