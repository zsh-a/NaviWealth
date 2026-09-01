import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
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

MarketCorporateAction _split() => MarketCorporateAction(
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
  exDate: DateTime.utc(2024, 1, 10),
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
      expect(
        await repository
            .watchObservations(
              ownerUserId: 'u-test',
              simulationId: simulation.id,
            )
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
      );
      await repository.recordObservation(
        simulation: simulation,
        observedAt: secondDay.add(const Duration(hours: 1)),
        weightedDailyChange: Decimal.parse('0.2'),
        pricedWeight: Decimal.one,
        missingQuoteWeight: Decimal.zero,
      );
      await repository.recordObservation(
        simulation: simulation,
        observedAt: thirdDay,
        weightedDailyChange: Decimal.parse('-0.1'),
        pricedWeight: Decimal.one,
        missingQuoteWeight: Decimal.zero,
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
        lifecycleAsOf: DateTime.utc(2024, 6, 21),
      );
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

      await repository.materializeDividendReferences(
        simulation: simulation,
        actionsByWatchlistItemId: {
          'cn_a:600519': [action],
        },
        trustedAdjustmentCoverageItemIds: const {'cn_a:600519'},
        lifecycleAsOf: DateTime.utc(2024, 6, 28),
      );
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

      final duplicate = await repository.materializeDividendReferences(
        simulation: simulation,
        actionsByWatchlistItemId: {
          'cn_a:600519': [action],
        },
        trustedAdjustmentCoverageItemIds: const {'cn_a:600519'},
        lifecycleAsOf: DateTime.utc(2024, 7, 1),
      );
      expect(duplicate, isEmpty);
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
