import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/features/finance/investment/data/watchlist_simulation_repository.dart';
import 'package:naviwealth/features/finance/market/domain/asset_market.dart';
import 'package:naviwealth/features/finance/market/domain/market_corporate_action.dart';

import '../../../../core/persistence/test_database.dart';
import '../../../../core/sync/_outbox_test_ext.dart';
import '../../data/repositories/_stub_stamper.dart';

MarketCorporateAction _dividend({
  required String revisionHash,
  required String cashPerShare,
  MarketCorporateActionStatus status = MarketCorporateActionStatus.implemented,
  String sourceKey = '600519:2024-12-31',
  DateTime? recordDate,
  DateTime? exDate,
  DateTime? payDate,
}) => MarketCorporateAction(
  id: 'eastmoney:RPT_SHAREBONUS_DET:$sourceKey',
  source: 'eastmoney',
  dataset: 'RPT_SHAREBONUS_DET',
  sourceKey: sourceKey,
  revisionHash: revisionHash,
  identityStrength: MarketCorporateActionIdentityStrength.strong,
  symbol: '600519',
  market: AssetMarket.cnA,
  kind: MarketCorporateActionKind.distribution,
  status: status,
  recordDate: recordDate ?? DateTime.utc(2024, 6, 20),
  exDate: exDate ?? DateTime.utc(2024, 6, 21),
  payDate: payDate ?? DateTime.utc(2024, 6, 21),
  currency: 'CNY',
  cashPerShare: Decimal.parse(cashPerShare),
);

MarketCorporateAction _split({bool omitExDate = false}) =>
    MarketCorporateAction(
      id: 'yfinance:chart:600519:split:2024-01-10',
      source: 'yfinance',
      dataset: 'chart',
      sourceKey: '600519:split:2024-01-10',
      revisionHash: 'split-revision',
      identityStrength: MarketCorporateActionIdentityStrength.strong,
      symbol: '600519',
      market: AssetMarket.cnA,
      kind: MarketCorporateActionKind.split,
      status: MarketCorporateActionStatus.unknown,
      announcementDate: DateTime.utc(2024, 1, 9),
      exDate: omitExDate ? null : DateTime.utc(2024, 1, 10),
      splitNumerator: 2,
      splitDenominator: 1,
    );

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
      expect(
        (await repository
                .watchObservations(
                  ownerUserId: 'u-test',
                  simulationId: simulation.id,
                )
                .first)
            .single
            .projectedValue,
        simulation.startingCapital,
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
        WatchlistSimulationRepository.allocationVersionsTable,
        WatchlistSimulationRepository.holdingVersionsTable,
        WatchlistSimulationRepository.holdingVersionsTable,
        WatchlistSimulationRepository.allocationHeadsTable,
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
        WatchlistSimulationRepository.allocationVersionsTable,
        WatchlistSimulationRepository.holdingVersionsTable,
        WatchlistSimulationRepository.allocationHeadsTable,
      ]);

      outbox.clearQueued();
      await repository.delete(simulation);
      expect(await repository.watchActive('u-test').first, isEmpty);
      final deletedSimulation = await (db.select(
        db.watchlistSimulations,
      )..where((table) => table.id.equals(simulation.id))).getSingle();
      expect(deletedSimulation.deletedAt, isNotNull);
      final rawObservationCount = await db
          .customSelect(
            'SELECT COUNT(*) AS count FROM watchlist_simulation_observations '
            'WHERE simulation_id = ?',
            variables: [Variable<String>(simulation.id)],
          )
          .getSingle();
      expect(rawObservationCount.read<int>('count'), 0);
      expect(
        await repository
            .watchPositions(ownerUserId: 'u-test', simulationId: simulation.id)
            .first,
        isEmpty,
      );
      final watchedAfterDelete = await repository
          .watchObservations(ownerUserId: 'u-test', simulationId: simulation.id)
          .first;
      final countAfterWatch = await db
          .customSelect(
            'SELECT COUNT(*) AS count FROM watchlist_simulation_observations '
            'WHERE simulation_id = ?',
            variables: [Variable<String>(simulation.id)],
          )
          .getSingle();
      expect(countAfterWatch.read<int>('count'), 0);
      expect(watchedAfterDelete, isEmpty);

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

  test(
    'compounds once per observed day and replaces same-day refreshes',
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
        name: 'Observed mix',
        baseCurrency: 'USD',
        startingCapital: Decimal.parse('1000'),
        targetWeights: {'us_stock:AAPL': Decimal.one},
        cashWeight: Decimal.zero,
      );
      final allocation = await repository.resolveAllocation(
        ownerUserId: 'u-test',
        simulationId: simulation.id,
      );
      final allocationBasisKey = allocation.allocationBasisKey!;
      final baselineDay = simulation.baselineAt;
      final secondDay = baselineDay.add(const Duration(days: 1));
      final thirdDay = baselineDay.add(const Duration(days: 2));
      final queuedBeforeObservations = outbox.queued.length;

      await repository.recordObservation(
        simulation: simulation,
        observedAt: secondDay,
        weightedDailyChange: Decimal.parse('0.1'),
        pricedWeight: Decimal.one,
        missingQuoteWeight: Decimal.zero,
        allocationBasisKey: allocationBasisKey,
      );
      await repository.recordObservation(
        simulation: simulation,
        observedAt: secondDay.add(const Duration(hours: 1)),
        weightedDailyChange: Decimal.parse('0.2'),
        pricedWeight: Decimal.one,
        missingQuoteWeight: Decimal.zero,
        allocationBasisKey: allocationBasisKey,
      );
      await repository.recordObservation(
        simulation: simulation,
        observedAt: thirdDay,
        weightedDailyChange: Decimal.parse('-0.1'),
        pricedWeight: Decimal.one,
        missingQuoteWeight: Decimal.zero,
        allocationBasisKey: allocationBasisKey,
      );

      final observations = await repository
          .watchObservations(ownerUserId: 'u-test', simulationId: simulation.id)
          .first;
      expect(observations, hasLength(3));
      expect(observations[0].projectedValue, Decimal.parse('1000'));
      expect(observations[1].projectedValue, Decimal.parse('1200.0'));
      expect(observations[2].projectedValue, Decimal.parse('1080.00'));
      expect(outbox.queued, hasLength(queuedBeforeObservations));
    },
  );

  test(
    'rehydrates local baseline before the first restored observation',
    () async {
      final db = makeTestDatabase();
      final repository = WatchlistSimulationRepository(
        db: db,
        outbox: InMemoryOutboxStore(),
        stamper: makeStubStamper(),
      );
      addTearDown(db.close);
      final simulation = await repository.create(
        collectionId: 'collection-growth',
        name: 'Restored simulation',
        baseCurrency: 'USD',
        startingCapital: Decimal.parse('1000'),
        targetWeights: {'us_stock:AAPL': Decimal.one},
        cashWeight: Decimal.zero,
      );
      final allocation = await repository.resolveAllocation(
        ownerUserId: 'u-test',
        simulationId: simulation.id,
      );
      await db.delete(db.watchlistSimulationObservations).go();

      final baseline = await repository
          .watchObservations(ownerUserId: 'u-test', simulationId: simulation.id)
          .first;
      expect(baseline, hasLength(1));
      expect(baseline.single.projectedValue, Decimal.parse('1000'));

      await repository.recordObservation(
        simulation: simulation,
        observedAt: simulation.baselineAt.add(const Duration(days: 1)),
        weightedDailyChange: Decimal.parse('0.1'),
        pricedWeight: Decimal.one,
        missingQuoteWeight: Decimal.zero,
        allocationBasisKey: allocation.allocationBasisKey!,
      );
      final observations = await repository
          .watchObservations(ownerUserId: 'u-test', simulationId: simulation.id)
          .first;
      expect(observations, hasLength(2));
      expect(observations.last.projectedValue, Decimal.parse('1100.0'));
    },
  );

  test(
    'materializes implemented dividends idempotently and applies revisions',
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
        collectionId: 'collection-cn',
        name: 'A-share income references',
        baseCurrency: 'CNY',
        startingCapital: Decimal.parse('100000'),
        targetWeights: {'cn_a:600519': Decimal.one},
        cashWeight: Decimal.zero,
      );
      outbox.clearQueued();

      final first = await repository.materializeDividendReferences(
        simulation: simulation,
        actionsByWatchlistItemId: {
          'cn_a:600519': [
            _dividend(revisionHash: 'revision-1', cashPerShare: '2.5'),
          ],
        },
      );
      final duplicate = await repository.materializeDividendReferences(
        simulation: simulation,
        actionsByWatchlistItemId: {
          'cn_a:600519': [
            _dividend(revisionHash: 'revision-1', cashPerShare: '2.5'),
          ],
        },
      );
      final revised = await repository.materializeDividendReferences(
        simulation: simulation,
        actionsByWatchlistItemId: {
          'cn_a:600519': [
            _dividend(revisionHash: 'revision-2', cashPerShare: '3.0'),
          ],
        },
      );

      expect(first, hasLength(1));
      expect(duplicate, isEmpty);
      expect(revised.single.id, first.single.id);
      final records = await repository
          .watchActionEntries(
            ownerUserId: 'u-test',
            simulationId: simulation.id,
          )
          .first;
      expect(records, hasLength(1));
      expect(records.single.revisionHash, 'revision-2');
      expect(records.single.cashPerShare, Decimal.parse('3.0'));
      expect(records.single.isReferenceOnly, isTrue);
      expect(records.single.eligibleQuantity, isNull);
      expect(records.single.grossAmount, isNull);
      expect(records.single.withholdingTaxAmount, isNull);
      expect(records.single.netAmount, isNull);
      expect(records.single.baseCurrencyAmount, isNull);
      expect(outbox.queued, hasLength(2));
      expect(
        outbox.queued.map((item) => item.table),
        everyElement(WatchlistSimulationRepository.actionEntriesTable),
      );

      for (final table in const [
        'investment_portfolios',
        'accounts',
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

  test(
    'holdings V2 captures baseline quantity and gross record-date entitlement',
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
        collectionId: 'collection-cn',
        name: 'Holdings V2',
        baseCurrency: 'CNY',
        startingCapital: Decimal.parse('1000'),
        targetWeights: {'cn_a:600519': Decimal.one},
        cashWeight: Decimal.zero,
        holdingInputs: {
          'cn_a:600519': WatchlistSimulationHoldingInput(
            symbol: '600519',
            market: AssetMarket.cnA,
            rawPrice: Decimal.parse('200'),
            priceCurrency: 'CNY',
            priceAsOf: DateTime.utc(2023, 11, 14),
            priceSource: 'fixture',
          ),
        },
      );

      expect(
        simulation.calculationMode,
        WatchlistSimulationCalculationMode.holdingsTotalReturnV2,
      );
      final allocation = await db
          .select(db.watchlistSimulationAllocationVersions)
          .getSingle();
      final holding = await db
          .select(db.watchlistSimulationHoldingVersions)
          .getSingle();
      expect(allocation.isComplete, isTrue);
      expect(
        allocation.reason,
        WatchlistSimulationAllocationReason.creation.name,
      );
      expect(holding.quantity, Decimal.parse('5'));
      expect(holding.rawPrice, Decimal.parse('200'));
      expect(holding.fxToBase, Decimal.one);

      await repository.materializeDividendReferences(
        simulation: simulation,
        actionsByWatchlistItemId: {
          'cn_a:600519': [
            _dividend(revisionHash: 'revision-v2', cashPerShare: '2.5'),
          ],
        },
        trustedAdjustmentCoverageItemIds: const {'cn_a:600519'},
      );
      final record =
          (await repository
                  .watchActionEntries(
                    ownerUserId: 'u-test',
                    simulationId: simulation.id,
                  )
                  .first)
              .single;
      expect(
        record.paperState,
        WatchlistSimulationPaperActionState.entitlementRecorded,
      );
      expect(record.eligibleQuantity, Decimal.parse('5'));
      expect(record.grossAmount, Decimal.parse('12.5'));
      expect(record.allocationBasisKey, isNotNull);
      expect(record.withholdingTaxAmount, isNull);
      expect(record.netAmount, isNull);
      expect(record.baseCurrencyAmount, isNull);

      final partialRevision = await repository.materializeDividendReferences(
        simulation: simulation,
        actionsByWatchlistItemId: {
          'cn_a:600519': [
            _dividend(revisionHash: 'partial-revision', cashPerShare: '3'),
          ],
        },
      );
      expect(partialRevision, isEmpty);
      final preserved =
          (await repository
                  .watchActionEntries(
                    ownerUserId: 'u-test',
                    simulationId: simulation.id,
                  )
                  .first)
              .single;
      expect(preserved.revisionHash, 'revision-v2');
      expect(preserved.grossAmount, Decimal.parse('12.5'));

      await (db.update(
        db.watchlistSimulationActionEntries,
      )..where((t) => t.id.equals(preserved.id))).write(
        const WatchlistSimulationActionEntriesCompanion(
          allocationBasisKey: Value(null),
        ),
      );
      await repository.materializeDividendReferences(
        simulation: simulation,
        actionsByWatchlistItemId: {
          'cn_a:600519': [
            _dividend(revisionHash: 'revision-v2', cashPerShare: '2.5'),
          ],
        },
        trustedAdjustmentCoverageItemIds: const {'cn_a:600519'},
      );
      final rematerialized =
          (await repository
                  .watchActionEntries(
                    ownerUserId: 'u-test',
                    simulationId: simulation.id,
                  )
                  .first)
              .single;
      expect(rematerialized.grossAmount, Decimal.parse('12.5'));
      expect(rematerialized.allocationBasisKey, isNotNull);
    },
  );

  test(
    'losing record-date lineage cannot advance trusted paper cash',
    () async {
      final db = makeTestDatabase();
      final repository = WatchlistSimulationRepository(
        db: db,
        outbox: InMemoryOutboxStore(),
        stamper: makeStubStamper(),
      );
      addTearDown(db.close);
      final simulation = await repository.create(
        collectionId: 'collection-cn',
        name: 'Lineage-safe dividend',
        baseCurrency: 'CNY',
        startingCapital: Decimal.parse('1000'),
        targetWeights: {'cn_a:600519': Decimal.one},
        cashWeight: Decimal.zero,
        holdingInputs: {
          'cn_a:600519': WatchlistSimulationHoldingInput(
            symbol: '600519',
            market: AssetMarket.cnA,
            rawPrice: Decimal.parse('200'),
            priceCurrency: 'CNY',
            priceAsOf: DateTime.utc(2023, 11, 14),
            priceSource: 'fixture',
          ),
        },
      );
      await repository.materializeDividendReferences(
        simulation: simulation,
        actionsByWatchlistItemId: {
          'cn_a:600519': [
            _dividend(revisionHash: 'lineage-a', cashPerShare: '2.5'),
          ],
        },
        trustedAdjustmentCoverageItemIds: const {'cn_a:600519'},
      );
      final trusted =
          (await repository
                  .watchActionEntries(
                    ownerUserId: 'u-test',
                    simulationId: simulation.id,
                  )
                  .first)
              .single;
      expect(trusted.grossAmount, Decimal.parse('12.5'));
      expect(trusted.allocationBasisKey, isNotNull);

      await repository.replaceAllocation(
        simulation: simulation,
        targetWeights: {'cn_a:000001': Decimal.one},
        cashWeight: Decimal.zero,
        holdingInputs: {
          'cn_a:000001': WatchlistSimulationHoldingInput(
            symbol: '000001',
            market: AssetMarket.cnA,
            rawPrice: Decimal.parse('10'),
            priceCurrency: 'CNY',
            priceAsOf: DateTime.utc(2023, 11, 15),
            priceSource: 'fixture',
          ),
        },
      );
      await repository.advanceDividendLifecycle(
        simulation: simulation,
        asOf: DateTime.utc(2025),
      );
      final cleared =
          (await repository
                  .watchActionEntries(
                    ownerUserId: 'u-test',
                    simulationId: simulation.id,
                  )
                  .first)
              .single;
      expect(
        cleared.paperState,
        WatchlistSimulationPaperActionState.referenceOnly,
      );
      expect(cleared.eligibleQuantity, isNull);
      expect(cleared.grossAmount, isNull);
      expect(cleared.receivableGrossAmount, isNull);
      expect(cleared.paperCashGrossAmount, isNull);
      expect(cleared.allocationBasisKey, isNull);
    },
  );

  test('trusted split history adjusts record-date virtual quantity', () async {
    final db = makeTestDatabase();
    final repository = WatchlistSimulationRepository(
      db: db,
      outbox: InMemoryOutboxStore(),
      stamper: makeStubStamper(),
    );
    addTearDown(db.close);
    final simulation = await repository.create(
      collectionId: 'collection-cn',
      name: 'Split-adjusted holdings',
      baseCurrency: 'CNY',
      startingCapital: Decimal.parse('1000'),
      targetWeights: {'cn_a:600519': Decimal.one},
      cashWeight: Decimal.zero,
      holdingInputs: {
        'cn_a:600519': WatchlistSimulationHoldingInput(
          symbol: '600519',
          market: AssetMarket.cnA,
          rawPrice: Decimal.parse('200'),
          priceCurrency: 'CNY',
          priceAsOf: DateTime.utc(2023, 11, 14),
          priceSource: 'fixture',
        ),
      },
    );

    await repository.materializeDividendReferences(
      simulation: simulation,
      actionsByWatchlistItemId: {
        'cn_a:600519': [
          _split(),
          _dividend(revisionHash: 'post-split', cashPerShare: '2.5'),
        ],
      },
      trustedAdjustmentCoverageItemIds: const {'cn_a:600519'},
    );
    final record =
        (await repository
                .watchActionEntries(
                  ownerUserId: 'u-test',
                  simulationId: simulation.id,
                )
                .first)
            .single;
    expect(record.eligibleQuantity, Decimal.parse('10'));
    expect(record.grossAmount, Decimal.parse('25.0'));
  });

  test('ambiguous adjustment date keeps dividend reference-only', () async {
    final db = makeTestDatabase();
    final repository = WatchlistSimulationRepository(
      db: db,
      outbox: InMemoryOutboxStore(),
      stamper: makeStubStamper(),
    );
    addTearDown(db.close);
    final simulation = await repository.create(
      collectionId: 'collection-cn',
      name: 'Ambiguous adjustment',
      baseCurrency: 'CNY',
      startingCapital: Decimal.parse('1000'),
      targetWeights: {'cn_a:600519': Decimal.one},
      cashWeight: Decimal.zero,
      holdingInputs: {
        'cn_a:600519': WatchlistSimulationHoldingInput(
          symbol: '600519',
          market: AssetMarket.cnA,
          rawPrice: Decimal.parse('200'),
          priceCurrency: 'CNY',
          priceAsOf: DateTime.utc(2023, 11, 14),
          priceSource: 'fixture',
        ),
      },
    );

    await repository.materializeDividendReferences(
      simulation: simulation,
      actionsByWatchlistItemId: {
        'cn_a:600519': [
          _split(omitExDate: true),
          _dividend(revisionHash: 'ambiguous-split', cashPerShare: '2.5'),
        ],
      },
      trustedAdjustmentCoverageItemIds: const {'cn_a:600519'},
    );
    final record =
        (await repository
                .watchActionEntries(
                  ownerUserId: 'u-test',
                  simulationId: simulation.id,
                )
                .first)
            .single;
    expect(
      record.paperState,
      WatchlistSimulationPaperActionState.referenceOnly,
    );
    expect(record.eligibleQuantity, isNull);
    expect(record.grossAmount, isNull);
  });

  test(
    'unchanged allocation save preserves trusted holding quantity',
    () async {
      final db = makeTestDatabase();
      final outbox = InMemoryOutboxStore();
      final repository = WatchlistSimulationRepository(
        db: db,
        outbox: outbox,
        stamper: makeStubStamper(),
      );
      addTearDown(db.close);
      final input = WatchlistSimulationHoldingInput(
        symbol: '600519',
        market: AssetMarket.cnA,
        rawPrice: Decimal.parse('200'),
        priceCurrency: 'CNY',
        priceAsOf: DateTime.utc(2023, 11, 14),
        priceSource: 'fixture',
      );
      final simulation = await repository.create(
        collectionId: 'collection-cn',
        name: 'No-op allocation',
        baseCurrency: 'CNY',
        startingCapital: Decimal.parse('1000'),
        targetWeights: {'cn_a:600519': Decimal.one},
        cashWeight: Decimal.zero,
        holdingInputs: {'cn_a:600519': input},
      );
      outbox.clearQueued();

      await repository.replaceAllocation(
        simulation: simulation,
        targetWeights: {'cn_a:600519': Decimal.one},
        cashWeight: Decimal.zero,
        holdingInputs: {'cn_a:600519': input},
      );

      expect(
        await db.select(db.watchlistSimulationAllocationVersions).get(),
        hasLength(1),
      );
      final holdings = await db
          .select(db.watchlistSimulationHoldingVersions)
          .get();
      expect(holdings, hasLength(1));
      expect(holdings.single.quantity, Decimal.parse('5'));
      expect(outbox.queued, isEmpty);
    },
  );

  test(
    'record-date allocation membership prevents removed holding reuse',
    () async {
      final db = makeTestDatabase();
      final repository = WatchlistSimulationRepository(
        db: db,
        outbox: InMemoryOutboxStore(),
        stamper: makeStubStamper(),
      );
      addTearDown(db.close);
      final simulation = await repository.create(
        collectionId: 'collection-cn',
        name: 'Effective allocation',
        baseCurrency: 'CNY',
        startingCapital: Decimal.parse('1000'),
        targetWeights: {
          'cn_a:600519': Decimal.parse('0.5'),
          'cn_a:000001': Decimal.parse('0.5'),
        },
        cashWeight: Decimal.zero,
        holdingInputs: {
          'cn_a:600519': WatchlistSimulationHoldingInput(
            symbol: '600519',
            market: AssetMarket.cnA,
            rawPrice: Decimal.parse('200'),
            priceCurrency: 'CNY',
            priceAsOf: DateTime.utc(2023, 11, 14),
            priceSource: 'fixture',
          ),
          'cn_a:000001': WatchlistSimulationHoldingInput(
            symbol: '000001',
            market: AssetMarket.cnA,
            rawPrice: Decimal.parse('10'),
            priceCurrency: 'CNY',
            priceAsOf: DateTime.utc(2023, 11, 14),
            priceSource: 'fixture',
          ),
        },
      );
      await repository.replaceAllocation(
        simulation: simulation,
        targetWeights: {'cn_a:000001': Decimal.one},
        cashWeight: Decimal.zero,
        holdingInputs: {
          'cn_a:000001': WatchlistSimulationHoldingInput(
            symbol: '000001',
            market: AssetMarket.cnA,
            rawPrice: Decimal.parse('10'),
            priceCurrency: 'CNY',
            priceAsOf: DateTime.utc(2023, 11, 14),
            priceSource: 'fixture',
          ),
        },
      );
      final heldRecordDate = simulation.baselineAt;
      final removedRecordDate = simulation.baselineAt.add(
        const Duration(days: 2),
      );
      await repository.materializeDividendReferences(
        simulation: simulation,
        actionsByWatchlistItemId: {
          'cn_a:600519': [
            _dividend(
              revisionHash: 'held',
              cashPerShare: '2.5',
              sourceKey: '600519:held',
              recordDate: heldRecordDate,
            ),
            _dividend(
              revisionHash: 'removed',
              cashPerShare: '2.5',
              sourceKey: '600519:removed',
              recordDate: removedRecordDate,
            ),
          ],
        },
        trustedAdjustmentCoverageItemIds: const {'cn_a:600519'},
        lifecycleAsOf: simulation.baselineAt,
      );
      final records = await repository
          .watchActionEntries(
            ownerUserId: 'u-test',
            simulationId: simulation.id,
          )
          .first;
      final bySourceKey = {
        for (final record in records) record.sourceKey: record,
      };
      expect(
        bySourceKey['600519:held']?.eligibleQuantity,
        Decimal.parse('2.5'),
      );
      expect(
        bySourceKey['600519:removed']?.paperState,
        WatchlistSimulationPaperActionState.referenceOnly,
      );
      expect(bySourceKey['600519:removed']?.eligibleQuantity, isNull);
    },
  );

  test('headed lineage traverses virtual pre-v91 predecessors', () async {
    final db = makeTestDatabase();
    final repository = WatchlistSimulationRepository(
      db: db,
      outbox: InMemoryOutboxStore(),
      stamper: makeStubStamper(),
    );
    addTearDown(db.close);
    final simulation = await repository.create(
      collectionId: 'collection-cn',
      name: 'Migrated lineage',
      baseCurrency: 'CNY',
      startingCapital: Decimal.parse('1000'),
      targetWeights: {'cn_a:600519': Decimal.one},
      cashWeight: Decimal.zero,
      holdingInputs: {
        'cn_a:600519': WatchlistSimulationHoldingInput(
          symbol: '600519',
          market: AssetMarket.cnA,
          rawPrice: Decimal.parse('200'),
          priceCurrency: 'CNY',
          priceAsOf: DateTime.utc(2023, 11, 14),
          priceSource: 'fixture',
        ),
      },
    );
    final legacyOne = await db
        .select(db.watchlistSimulationAllocationVersions)
        .getSingle();
    await (db.update(
      db.watchlistSimulationAllocationVersions,
    )..where((t) => t.id.equals(legacyOne.id))).write(
      const WatchlistSimulationAllocationVersionsCompanion(
        requiresExplicitHead: Value(false),
      ),
    );
    final legacyTwoAt = legacyOne.effectiveAt.add(const Duration(days: 1));
    final headedAt = legacyTwoAt.add(const Duration(days: 1));

    Future<void> insertVersion({
      required String id,
      required DateTime effectiveAt,
      required Decimal quantity,
      required bool explicit,
      String? previousId,
    }) async {
      final hlc = Hlc(
        wallMillis: effectiveAt.millisecondsSinceEpoch,
        counter: 0,
        nodeId: 'dev-$id',
      );
      await db
          .into(db.watchlistSimulationAllocationVersions)
          .insert(
            WatchlistSimulationAllocationVersionsCompanion.insert(
              id: id,
              simulationId: simulation.id,
              effectiveAt: effectiveAt,
              reason: WatchlistSimulationAllocationReason.reallocation.name,
              previousAllocationVersionId: Value(previousId),
              requiresExplicitHead: Value(explicit),
              cashWeight: Decimal.zero,
              isComplete: const Value(true),
              createdAt: effectiveAt,
              ownerUserId: 'u-test',
              updatedAt: effectiveAt,
              updatedByDevice: 'dev-$id',
              hlc: hlc,
            ),
          );
      await db
          .into(db.watchlistSimulationHoldingVersions)
          .insert(
            WatchlistSimulationHoldingVersionsCompanion.insert(
              id: 'holding-$id',
              allocationVersionId: id,
              simulationId: simulation.id,
              watchlistItemId: 'cn_a:600519',
              symbol: '600519',
              market: AssetMarket.cnA.wire,
              targetWeight: Decimal.one,
              quantity: Value(quantity),
              rawPrice: const Value(null),
              priceCurrency: const Value('CNY'),
              priceAsOf: Value(effectiveAt),
              priceSource: const Value('fixture'),
              fxToBase: Value(Decimal.one),
              effectiveAt: effectiveAt,
              createdAt: effectiveAt,
              ownerUserId: 'u-test',
              updatedAt: effectiveAt,
              updatedByDevice: 'dev-$id',
              hlc: hlc,
            ),
          );
    }

    await insertVersion(
      id: 'legacy-two',
      effectiveAt: legacyTwoAt,
      quantity: Decimal.parse('10'),
      explicit: false,
    );
    await insertVersion(
      id: 'headed-three',
      effectiveAt: headedAt,
      quantity: Decimal.parse('20'),
      explicit: true,
      previousId: 'legacy-two',
    );
    await (db.update(
      db.watchlistSimulationAllocationHeads,
    )..where((t) => t.id.equals(simulation.id))).write(
      WatchlistSimulationAllocationHeadsCompanion(
        allocationVersionId: const Value('headed-three'),
        updatedAt: Value(headedAt),
        updatedByDevice: const Value('dev-headed-three'),
        hlc: Value(
          Hlc(
            wallMillis: headedAt.millisecondsSinceEpoch,
            counter: 0,
            nodeId: 'dev-headed-three',
          ),
        ),
      ),
    );

    MarketCorporateAction at(String key, DateTime recordDate) => _dividend(
      revisionHash: key,
      cashPerShare: '1',
      sourceKey: key,
      recordDate: recordDate,
      exDate: recordDate.add(const Duration(hours: 1)),
      payDate: recordDate.add(const Duration(hours: 2)),
    );
    await repository.materializeDividendReferences(
      simulation: simulation,
      actionsByWatchlistItemId: {
        'cn_a:600519': [
          at(
            'legacy-one-action',
            legacyOne.effectiveAt.add(const Duration(hours: 12)),
          ),
          at('legacy-two-action', legacyTwoAt.add(const Duration(hours: 12))),
          at('headed-three-action', headedAt.add(const Duration(hours: 12))),
        ],
      },
      trustedAdjustmentCoverageItemIds: const {'cn_a:600519'},
      lifecycleAsOf: legacyOne.effectiveAt,
    );
    final actions = await repository
        .watchActionEntries(ownerUserId: 'u-test', simulationId: simulation.id)
        .first;
    final quantities = {
      for (final action in actions) action.sourceKey: action.eligibleQuantity,
    };
    expect(quantities['legacy-one-action'], Decimal.parse('5'));
    expect(quantities['legacy-two-action'], Decimal.parse('10'));
    expect(quantities['headed-three-action'], Decimal.parse('20'));
  });

  test('quantity remains unknown when quote identity is mismatched', () async {
    final db = makeTestDatabase();
    final repository = WatchlistSimulationRepository(
      db: db,
      outbox: InMemoryOutboxStore(),
      stamper: makeStubStamper(),
    );
    addTearDown(db.close);
    await repository.create(
      collectionId: 'collection-cn',
      name: 'Mismatched evidence',
      baseCurrency: 'CNY',
      startingCapital: Decimal.parse('1000'),
      targetWeights: {'cn_a:600519': Decimal.one},
      cashWeight: Decimal.zero,
      holdingInputs: {
        'cn_a:600519': WatchlistSimulationHoldingInput(
          symbol: '000001',
          market: AssetMarket.cnA,
          rawPrice: Decimal.parse('10'),
          priceCurrency: 'CNY',
          priceAsOf: DateTime.utc(2023, 11, 14),
          priceSource: 'fixture',
        ),
      },
    );
    final holding = await db
        .select(db.watchlistSimulationHoldingVersions)
        .getSingle();
    expect(holding.quantity, isNull);
  });

  test(
    'moves gross entitlement from receivable to pending-tax paper cash',
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
        collectionId: 'collection-cn',
        name: 'Dividend lifecycle',
        baseCurrency: 'CNY',
        startingCapital: Decimal.parse('1000'),
        targetWeights: {'cn_a:600519': Decimal.one},
        cashWeight: Decimal.zero,
        holdingInputs: {
          'cn_a:600519': WatchlistSimulationHoldingInput(
            symbol: '600519',
            market: AssetMarket.cnA,
            rawPrice: Decimal.parse('200'),
            priceCurrency: 'CNY',
            priceAsOf: DateTime.utc(2023, 11, 14),
            priceSource: 'fixture',
          ),
        },
      );
      final action = _dividend(
        revisionHash: 'lifecycle',
        cashPerShare: '2.5',
        payDate: DateTime.utc(2024, 6, 28),
      );

      await repository.materializeDividendReferences(
        simulation: simulation,
        actionsByWatchlistItemId: {
          'cn_a:600519': [action],
        },
        trustedAdjustmentCoverageItemIds: const {'cn_a:600519'},
        lifecycleAsOf: DateTime.utc(2024, 6, 20),
      );
      final receivableTransition = await repository.advanceDividendLifecycle(
        simulation: simulation,
        asOf: DateTime.utc(2024, 6, 21),
      );
      expect(receivableTransition, hasLength(1));
      var record =
          (await repository
                  .watchActionEntries(
                    ownerUserId: 'u-test',
                    simulationId: simulation.id,
                  )
                  .first)
              .single;
      expect(
        record.paperState,
        WatchlistSimulationPaperActionState.receivableGross,
      );
      expect(record.grossAmount, Decimal.parse('12.5'));
      expect(record.receivableGrossAmount, Decimal.parse('12.5'));
      expect(record.paperCashGrossAmount, isNull);
      expect(record.stateAt, DateTime.utc(2024, 6, 21));

      final cashTransition = await repository.advanceDividendLifecycle(
        simulation: simulation,
        asOf: DateTime.utc(2024, 6, 28),
      );
      expect(cashTransition, hasLength(1));
      record =
          (await repository
                  .watchActionEntries(
                    ownerUserId: 'u-test',
                    simulationId: simulation.id,
                  )
                  .first)
              .single;
      expect(
        record.paperState,
        WatchlistSimulationPaperActionState.grossCashPendingTax,
      );
      expect(record.receivableGrossAmount, isNull);
      expect(record.paperCashGrossAmount, Decimal.parse('12.5'));
      expect(record.stateAt, DateTime.utc(2024, 6, 28));
      expect(record.withholdingTaxAmount, isNull);
      expect(record.netAmount, isNull);
      expect(record.baseCurrencyAmount, isNull);

      final duplicate = await repository.advanceDividendLifecycle(
        simulation: simulation,
        asOf: DateTime.utc(2024, 6, 21),
      );
      expect(duplicate, isEmpty);
      final earlierProviderReplay = await repository
          .materializeDividendReferences(
            simulation: simulation,
            actionsByWatchlistItemId: {
              'cn_a:600519': [action],
            },
            trustedAdjustmentCoverageItemIds: const {'cn_a:600519'},
            lifecycleAsOf: DateTime.utc(2024, 6, 20),
          );
      expect(earlierProviderReplay, isEmpty);
      final nonFinalRevision = await repository.materializeDividendReferences(
        simulation: simulation,
        actionsByWatchlistItemId: {
          'cn_a:600519': [
            _dividend(
              revisionHash: 'regressed-proposal',
              cashPerShare: '2.5',
              status: MarketCorporateActionStatus.proposed,
            ),
          ],
        },
        trustedAdjustmentCoverageItemIds: const {'cn_a:600519'},
        lifecycleAsOf: DateTime.utc(2024, 7, 1),
      );
      expect(nonFinalRevision, isEmpty);
      final preserved =
          (await repository
                  .watchActionEntries(
                    ownerUserId: 'u-test',
                    simulationId: simulation.id,
                  )
                  .first)
              .single;
      expect(
        preserved.paperState,
        WatchlistSimulationPaperActionState.grossCashPendingTax,
      );
      expect(preserved.revisionHash, 'lifecycle');
      final observations = await repository
          .watchObservations(ownerUserId: 'u-test', simulationId: simulation.id)
          .first;
      expect(observations, hasLength(1));
      expect(observations.single.projectedValue, Decimal.parse('1000'));

      for (final table in const [
        'investment_portfolios',
        'accounts',
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

  test('holdings V2 never treats missing FX as one', () async {
    final db = makeTestDatabase();
    final repository = WatchlistSimulationRepository(
      db: db,
      outbox: InMemoryOutboxStore(),
      stamper: makeStubStamper(),
    );
    addTearDown(db.close);
    final simulation = await repository.create(
      collectionId: 'collection-cn',
      name: 'Cross-currency holdings',
      baseCurrency: 'USD',
      startingCapital: Decimal.parse('1000'),
      targetWeights: {'cn_a:600519': Decimal.one},
      cashWeight: Decimal.zero,
      holdingInputs: {
        'cn_a:600519': WatchlistSimulationHoldingInput(
          symbol: '600519',
          market: AssetMarket.cnA,
          rawPrice: Decimal.parse('200'),
          priceCurrency: 'CNY',
          priceAsOf: DateTime.utc(2023, 11, 14),
          priceSource: 'fixture',
        ),
      },
    );

    final allocation = await db
        .select(db.watchlistSimulationAllocationVersions)
        .getSingle();
    final holding = await db
        .select(db.watchlistSimulationHoldingVersions)
        .getSingle();
    expect(allocation.isComplete, isFalse);
    expect(holding.quantity, isNull);
    expect(holding.fxToBase, isNull);

    await repository.materializeDividendReferences(
      simulation: simulation,
      actionsByWatchlistItemId: {
        'cn_a:600519': [
          _dividend(revisionHash: 'revision-fx', cashPerShare: '2.5'),
        ],
      },
      trustedAdjustmentCoverageItemIds: const {'cn_a:600519'},
    );
    final record =
        (await repository
                .watchActionEntries(
                  ownerUserId: 'u-test',
                  simulationId: simulation.id,
                )
                .first)
            .single;
    expect(
      record.paperState,
      WatchlistSimulationPaperActionState.referenceOnly,
    );
    expect(record.eligibleQuantity, isNull);
    expect(record.grossAmount, isNull);
  });

  test(
    'records cancellation revisions but ignores new unimplemented plans',
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
        collectionId: 'collection-cn',
        name: 'Cancellation references',
        baseCurrency: 'CNY',
        startingCapital: Decimal.parse('100000'),
        targetWeights: {'cn_a:600519': Decimal.one},
        cashWeight: Decimal.zero,
      );

      await repository.materializeDividendReferences(
        simulation: simulation,
        actionsByWatchlistItemId: {
          'cn_a:600519': [
            _dividend(revisionHash: 'revision-1', cashPerShare: '2.5'),
            _dividend(
              revisionHash: 'proposal',
              cashPerShare: '1.0',
              status: MarketCorporateActionStatus.proposed,
              sourceKey: '600519:2025-03-31',
            ),
          ],
        },
      );
      await repository.materializeDividendReferences(
        simulation: simulation,
        actionsByWatchlistItemId: {
          'cn_a:600519': [
            _dividend(
              revisionHash: 'revision-cancelled',
              cashPerShare: '2.5',
              status: MarketCorporateActionStatus.cancelled,
            ),
          ],
        },
      );

      final records = await repository
          .watchActionEntries(
            ownerUserId: 'u-test',
            simulationId: simulation.id,
          )
          .first;
      expect(records, hasLength(1));
      expect(records.single.status, MarketCorporateActionStatus.cancelled);
      expect(records.single.revisionHash, 'revision-cancelled');

      outbox.clearQueued();
      await repository.delete(simulation);
      expect(
        await repository
            .watchActionEntries(
              ownerUserId: 'u-test',
              simulationId: simulation.id,
            )
            .first,
        isEmpty,
      );
      expect(
        outbox.queued.map((item) => item.table),
        contains(WatchlistSimulationRepository.actionEntriesTable),
      );
    },
  );

  test('explicit protocol evidence blocks compatibility fallback', () async {
    final db = makeTestDatabase();
    final repository = WatchlistSimulationRepository(
      db: db,
      outbox: InMemoryOutboxStore(),
      stamper: makeStubStamper(),
    );
    addTearDown(db.close);
    final simulation = await repository.create(
      collectionId: 'collection-growth',
      name: 'Paged mix',
      baseCurrency: 'USD',
      startingCapital: Decimal.parse('1000'),
      targetWeights: {'us_stock:AAPL': Decimal.parse('0.6')},
      cashWeight: Decimal.parse('0.4'),
    );
    await (db.delete(
      db.watchlistSimulationAllocationHeads,
    )..where((t) => t.simulationId.equals(simulation.id))).go();
    await (db.delete(
      db.watchlistSimulationHoldingVersions,
    )..where((t) => t.simulationId.equals(simulation.id))).go();
    await (db.delete(
      db.watchlistSimulationAllocationVersions,
    )..where((t) => t.simulationId.equals(simulation.id))).go();
    await (db.update(
      db.watchlistSimulations,
    )..where((t) => t.id.equals(simulation.id))).write(
      const WatchlistSimulationsCompanion(allocationProtocolVersion: Value(0)),
    );
    await (db.update(
      db.watchlistSimulationPositions,
    )..where((t) => t.simulationId.equals(simulation.id))).write(
      const WatchlistSimulationPositionsCompanion(
        requiresExplicitHead: Value(false),
      ),
    );
    expect(
      (await repository.resolveAllocation(
        ownerUserId: 'u-test',
        simulationId: simulation.id,
      )).status,
      WatchlistSimulationAllocationStatus.legacyFallback,
    );

    await db
        .into(db.watchlistSimulationAllocationHeads)
        .insert(
          WatchlistSimulationAllocationHeadsCompanion.insert(
            id: simulation.id,
            simulationId: simulation.id,
            allocationVersionId: 'missing-tombstoned-head-version',
            createdAt: simulation.createdAt,
            ownerUserId: 'u-test',
            updatedAt: simulation.createdAt,
            updatedByDevice: 'dev-tombstoned-head',
            hlc: Hlc.parse('1700000002000.0000-dev-tombstoned-head'),
            deletedAt: Value(simulation.createdAt),
          ),
        );
    expect(
      (await repository.resolveAllocation(
        ownerUserId: 'u-test',
        simulationId: simulation.id,
      )).status,
      WatchlistSimulationAllocationStatus.pending,
    );
    await (db.delete(
      db.watchlistSimulationAllocationHeads,
    )..where((t) => t.id.equals(simulation.id))).go();

    await (db.update(
      db.watchlistSimulationPositions,
    )..where((t) => t.simulationId.equals(simulation.id))).write(
      const WatchlistSimulationPositionsCompanion(
        requiresExplicitHead: Value(true),
      ),
    );
    expect(
      (await repository.resolveAllocation(
        ownerUserId: 'u-test',
        simulationId: simulation.id,
      )).status,
      WatchlistSimulationAllocationStatus.pending,
    );

    await (db.update(
      db.watchlistSimulationPositions,
    )..where((t) => t.simulationId.equals(simulation.id))).write(
      const WatchlistSimulationPositionsCompanion(
        requiresExplicitHead: Value(false),
      ),
    );
    await (db.update(
      db.watchlistSimulations,
    )..where((t) => t.id.equals(simulation.id))).write(
      const WatchlistSimulationsCompanion(allocationProtocolVersion: Value(1)),
    );
    expect(
      (await repository.resolveAllocation(
        ownerUserId: 'u-test',
        simulationId: simulation.id,
      )).status,
      WatchlistSimulationAllocationStatus.pending,
    );

    await (db.update(
      db.watchlistSimulations,
    )..where((t) => t.id.equals(simulation.id))).write(
      const WatchlistSimulationsCompanion(allocationProtocolVersion: Value(0)),
    );
    await db
        .into(db.watchlistSimulationAllocationVersions)
        .insert(
          WatchlistSimulationAllocationVersionsCompanion.insert(
            id: 'explicit-tombstone',
            simulationId: simulation.id,
            effectiveAt: simulation.createdAt,
            reason: WatchlistSimulationAllocationReason.reallocation.name,
            requiresExplicitHead: const Value(true),
            cashWeight: Decimal.one,
            isComplete: const Value(true),
            createdAt: simulation.createdAt,
            ownerUserId: 'u-test',
            updatedAt: simulation.createdAt,
            updatedByDevice: 'dev-tombstone',
            hlc: Hlc.parse('1700000003000.0000-dev-tombstone'),
            deletedAt: Value(simulation.createdAt),
          ),
        );
    expect(
      (await repository.resolveAllocation(
        ownerUserId: 'u-test',
        simulationId: simulation.id,
      )).status,
      WatchlistSimulationAllocationStatus.pending,
    );
  });

  test(
    'atomic head selects one concurrent branch and blocks partial pages',
    () async {
      final db = makeTestDatabase();
      final repository = WatchlistSimulationRepository(
        db: db,
        outbox: InMemoryOutboxStore(),
        stamper: makeStubStamper(),
      );
      addTearDown(db.close);
      final simulation = await repository.create(
        collectionId: 'collection-growth',
        name: 'Concurrent mix',
        baseCurrency: 'USD',
        startingCapital: Decimal.parse('1000'),
        targetWeights: {'us_stock:AAPL': Decimal.parse('0.6')},
        cashWeight: Decimal.parse('0.4'),
      );
      final baseHead = await (db.select(
        db.watchlistSimulationAllocationHeads,
      )..where((t) => t.id.equals(simulation.id))).getSingle();
      final now = simulation.createdAt.add(const Duration(seconds: 1));

      Future<void> insertBranch({
        required String id,
        required String itemId,
        required Decimal targetWeight,
        required Decimal cashWeight,
        required String hlc,
      }) async {
        await db
            .into(db.watchlistSimulationAllocationVersions)
            .insert(
              WatchlistSimulationAllocationVersionsCompanion.insert(
                id: id,
                simulationId: simulation.id,
                effectiveAt: now,
                reason: WatchlistSimulationAllocationReason.reallocation.name,
                previousAllocationVersionId: Value(
                  baseHead.allocationVersionId,
                ),
                requiresExplicitHead: const Value(true),
                cashWeight: cashWeight,
                isComplete: const Value(true),
                createdAt: now,
                ownerUserId: 'u-test',
                updatedAt: now,
                updatedByDevice: 'dev-$id',
                hlc: Hlc.parse(hlc),
              ),
            );
        await db
            .into(db.watchlistSimulationHoldingVersions)
            .insert(
              WatchlistSimulationHoldingVersionsCompanion.insert(
                id: 'holding-$id',
                allocationVersionId: id,
                simulationId: simulation.id,
                watchlistItemId: itemId,
                symbol: itemId.split(':').last,
                market: 'us_stock',
                targetWeight: targetWeight,
                effectiveAt: now,
                createdAt: now,
                ownerUserId: 'u-test',
                updatedAt: now,
                updatedByDevice: 'dev-$id',
                hlc: Hlc.parse(hlc),
              ),
            );
      }

      await insertBranch(
        id: 'branch-a',
        itemId: 'us_stock:GOOG',
        targetWeight: Decimal.parse('0.6'),
        cashWeight: Decimal.parse('0.4'),
        hlc: '1700000001000.0000-dev-a',
      );
      await insertBranch(
        id: 'branch-b',
        itemId: 'us_stock:MSFT',
        targetWeight: Decimal.parse('0.5'),
        cashWeight: Decimal.parse('0.5'),
        hlc: '1700000001000.0000-dev-b',
      );
      await db
          .into(db.watchlistSimulationPositions)
          .insert(
            WatchlistSimulationPositionsCompanion.insert(
              id: 'legacy-merged-msft',
              simulationId: simulation.id,
              watchlistItemId: 'us_stock:MSFT',
              targetWeight: Decimal.parse('0.5'),
              createdAt: now,
              ownerUserId: 'u-test',
              updatedAt: now,
              updatedByDevice: 'dev-b',
              hlc: Hlc.parse('1700000001000.0000-dev-b'),
            ),
          );
      await (db.update(
        db.watchlistSimulationAllocationHeads,
      )..where((t) => t.id.equals(simulation.id))).write(
        WatchlistSimulationAllocationHeadsCompanion(
          allocationVersionId: const Value('branch-b'),
          updatedByDevice: const Value('dev-b'),
          hlc: Value(Hlc.parse('1700000001000.0000-dev-b')),
        ),
      );

      final rawLegacy = await (db.select(
        db.watchlistSimulationPositions,
      )..where((t) => t.simulationId.equals(simulation.id))).get();
      final impossibleLegacyTotal = rawLegacy.fold<Decimal>(
        simulation.cashWeight,
        (sum, row) => sum + row.targetWeight,
      );
      expect(impossibleLegacyTotal, Decimal.parse('1.5'));
      final selected = await repository.resolveAllocation(
        ownerUserId: 'u-test',
        simulationId: simulation.id,
      );
      expect(selected.status, WatchlistSimulationAllocationStatus.selected);
      expect(selected.cashWeight, Decimal.parse('0.5'));
      expect(selected.positions.single.watchlistItemId, 'us_stock:MSFT');
      final targets = await repository.listActionTargets(
        ownerUserId: 'u-test',
        simulationId: simulation.id,
      );
      expect(
        targets.map((target) => target.watchlistItemId),
        containsAll(<String>['us_stock:AAPL', 'us_stock:MSFT']),
      );
      expect(
        targets.map((target) => target.watchlistItemId),
        isNot(contains('us_stock:GOOG')),
      );

      final branchBDay = simulation.baselineAt.add(const Duration(days: 1));
      await repository.recordObservation(
        simulation: simulation,
        observedAt: branchBDay,
        weightedDailyChange: Decimal.parse('0.1'),
        pricedWeight: Decimal.one,
        missingQuoteWeight: Decimal.zero,
        allocationBasisKey: selected.allocationBasisKey!,
      );
      await (db.update(
        db.watchlistSimulationAllocationHeads,
      )..where((t) => t.id.equals(simulation.id))).write(
        WatchlistSimulationAllocationHeadsCompanion(
          allocationVersionId: const Value('branch-a'),
          updatedByDevice: const Value('dev-a'),
          hlc: Value(Hlc.parse('1700000001500.0000-dev-a')),
        ),
      );
      await expectLater(
        repository.recordObservation(
          simulation: simulation,
          observedAt: branchBDay.add(const Duration(hours: 1)),
          weightedDailyChange: Decimal.parse('0.1'),
          pricedWeight: Decimal.one,
          missingQuoteWeight: Decimal.zero,
          allocationBasisKey: selected.allocationBasisKey!,
        ),
        throwsStateError,
      );
      final branchA = await repository.resolveAllocation(
        ownerUserId: 'u-test',
        simulationId: simulation.id,
      );
      await repository.recordObservation(
        simulation: simulation,
        observedAt: simulation.baselineAt.add(const Duration(days: 2)),
        weightedDailyChange: Decimal.parse('0.2'),
        pricedWeight: Decimal.one,
        missingQuoteWeight: Decimal.zero,
        allocationBasisKey: branchA.allocationBasisKey!,
      );
      final convergedObservations = await repository
          .watchObservations(ownerUserId: 'u-test', simulationId: simulation.id)
          .first;
      expect(convergedObservations, hasLength(2));
      expect(
        convergedObservations.last.projectedValue,
        Decimal.parse('1200.0'),
      );

      await (db.update(
        db.watchlistSimulationAllocationHeads,
      )..where((t) => t.id.equals(simulation.id))).write(
        WatchlistSimulationAllocationHeadsCompanion(
          allocationVersionId: const Value('missing-page'),
          updatedByDevice: const Value('dev-c'),
          hlc: Value(Hlc.parse('1700000002000.0000-dev-c')),
        ),
      );
      expect(
        (await repository.resolveAllocation(
          ownerUserId: 'u-test',
          simulationId: simulation.id,
        )).status,
        WatchlistSimulationAllocationStatus.pending,
      );
      await db
          .into(db.watchlistSimulationAllocationVersions)
          .insert(
            WatchlistSimulationAllocationVersionsCompanion.insert(
              id: 'missing-page',
              simulationId: simulation.id,
              effectiveAt: now.add(const Duration(seconds: 1)),
              reason: WatchlistSimulationAllocationReason.reallocation.name,
              previousAllocationVersionId: const Value('branch-b'),
              requiresExplicitHead: const Value(true),
              cashWeight: Decimal.one,
              isComplete: const Value(true),
              createdAt: now,
              ownerUserId: 'u-test',
              updatedAt: now,
              updatedByDevice: 'dev-c',
              hlc: Hlc.parse('1700000002000.0000-dev-c'),
            ),
          );
      final recovered = await repository.resolveAllocation(
        ownerUserId: 'u-test',
        simulationId: simulation.id,
      );
      expect(recovered.status, WatchlistSimulationAllocationStatus.selected);
      expect(recovered.cashWeight, Decimal.one);
      expect(recovered.positions, isEmpty);
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
