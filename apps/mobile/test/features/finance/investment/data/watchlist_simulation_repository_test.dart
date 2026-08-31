import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/features/finance/investment/data/watchlist_simulation_repository.dart';

import '../../../../core/persistence/test_database.dart';
import '../../../../core/sync/_outbox_test_ext.dart';
import '../../data/repositories/_stub_stamper.dart';

void main() {
  test(
    'creates, reallocates, and deletes only paper simulation rows',
    () async {
      final db = makeTestDatabase();
      final outbox = InMemoryOutboxStore();
      final repository = WatchlistSimulationRepository(
        db: db,
        outbox: outbox,
        stamper: makeStubStamper(),
      );
      addTearDown(db.close);

      final simulation = await repository.create(
        collectionId: 'collection-growth',
        name: 'Growth paper mix',
        baseCurrency: 'usd',
        startingCapital: Decimal.parse('100000.50'),
        targetWeights: {
          'us_stock:AAPL': Decimal.parse('0.6'),
          'us_stock:MSFT': Decimal.parse('0.3'),
        },
        cashWeight: Decimal.parse('0.1'),
      );

      expect(simulation.baseCurrency, 'USD');
      expect(simulation.startingCapital, Decimal.parse('100000.50'));
      expect(
        (await repository.watchActive('u-test').first).single.id,
        simulation.id,
      );
      final createdPositions = await repository
          .watchPositions(ownerUserId: 'u-test', simulationId: simulation.id)
          .first;
      expect(createdPositions, hasLength(2));
      expect(
        createdPositions.map((position) => position.targetWeight).toSet(),
        {Decimal.parse('0.6'), Decimal.parse('0.3')},
      );
      expect(outbox.queued.map((item) => item.table), [
        WatchlistSimulationRepository.simulationsTable,
        WatchlistSimulationRepository.positionsTable,
        WatchlistSimulationRepository.positionsTable,
      ]);

      outbox.clearQueued();
      await repository.replaceAllocation(
        simulation: simulation,
        targetWeights: {'us_stock:AAPL': Decimal.parse('0.5')},
        cashWeight: Decimal.parse('0.5'),
      );
      final reallocated = await repository
          .watchPositions(ownerUserId: 'u-test', simulationId: simulation.id)
          .first;
      expect(reallocated, hasLength(1));
      expect(reallocated.single.watchlistItemId, 'us_stock:AAPL');
      expect(reallocated.single.targetWeight, Decimal.parse('0.5'));
      expect(outbox.queued.map((item) => item.table), [
        WatchlistSimulationRepository.simulationsTable,
        WatchlistSimulationRepository.positionsTable,
        WatchlistSimulationRepository.positionsTable,
      ]);

      outbox.clearQueued();
      await repository.delete(simulation);
      expect(await repository.watchActive('u-test').first, isEmpty);
      expect(
        await repository
            .watchPositions(ownerUserId: 'u-test', simulationId: simulation.id)
            .first,
        isEmpty,
      );

      for (final table in const [
        'investment_portfolios',
        'journal_entries',
        'postings',
      ]) {
        final count = await db
            .customSelect('SELECT COUNT(*) AS count FROM $table')
            .getSingle();
        expect(count.read<int>('count'), 0, reason: table);
      }
    },
  );

  test('rejects invalid allocation totals before writing', () async {
    final db = makeTestDatabase();
    final repository = WatchlistSimulationRepository(
      db: db,
      outbox: InMemoryOutboxStore(),
      stamper: makeStubStamper(),
    );
    addTearDown(db.close);

    await expectLater(
      repository.create(
        collectionId: 'collection-growth',
        name: 'Invalid mix',
        baseCurrency: 'USD',
        startingCapital: Decimal.parse('1000'),
        targetWeights: {'us_stock:AAPL': Decimal.parse('0.8')},
        cashWeight: Decimal.parse('0.1'),
      ),
      throwsArgumentError,
    );
    expect(await repository.watchActive('u-test').first, isEmpty);
  });
}
