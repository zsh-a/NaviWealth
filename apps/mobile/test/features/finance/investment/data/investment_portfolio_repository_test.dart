import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/finance/home/domain/dashboard_models.dart';
import 'package:naviwealth/features/finance/investment/data/investment_portfolio_providers.dart';
import 'package:naviwealth/features/finance/investment/data/investment_portfolio_repository.dart';
import 'package:naviwealth/features/finance/investment/domain/models/holding_snapshot.dart';
import 'package:naviwealth/features/finance/investment/domain/models/lot.dart';
import 'package:naviwealth/features/finance/investment/domain/models/portfolio_capital_assignment.dart';
import 'package:naviwealth/features/finance/investment/domain/strategy/portfolio_strategy.dart';
import 'package:naviwealth/features/finance/rebalance/data/rebalance_providers.dart';
import 'package:naviwealth/features/finance/rebalance/domain/allocation_schemes.dart';
import 'package:naviwealth/features/finance/rebalance/domain/rebalance_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/persistence/test_database.dart';
import '../../../../core/sync/_outbox_test_ext.dart';
import '../../data/repositories/_stub_stamper.dart';

void main() {
  group('InvestmentPortfolioRepository', () {
    test(
      'creates a complete aggregate and enforces whole-lot ownership',
      () async {
        final db = makeTestDatabase();
        final outbox = InMemoryOutboxStore();
        final repository = InvestmentPortfolioRepository(
          db: db,
          outbox: outbox,
          stamper: makeStubStamper(),
        );
        addTearDown(db.close);

        final income = await repository.create(
          name: ' Dividend income ',
          initialStrategyKind: PortfolioStrategyKind.dividendIncome,
        );
        final growth = await repository.create(
          name: 'Growth',
          initialStrategyKind: PortfolioStrategyKind.indexCore,
        );
        expect(income.name, 'Dividend income');
        expect(await repository.watchActive('u-test').first, hasLength(2));

        final groups = await repository.watchGroups('u-test').first;
        final incomeGroup = groups.singleWhere(
          (group) => group.portfolioId == income.id,
        );
        final growthGroup = groups.singleWhere(
          (group) => group.portfolioId == growth.id,
        );
        expect(incomeGroup.targetWeightBps, 10000);
        expect(
          (await repository.watchStrategies('u-test').first).every(
            (strategy) => strategy.capitalRole == StrategyCapitalRole.owner,
          ),
          isTrue,
        );

        await repository.assignWholeLot(
          lotId: 'lot-1',
          portfolioId: income.id,
          rebalanceGroupId: incomeGroup.id,
        );
        await expectLater(
          repository.assignWholeLot(
            lotId: 'lot-1',
            portfolioId: growth.id,
            rebalanceGroupId: growthGroup.id,
          ),
          throwsStateError,
        );
        final assigned =
            (await repository.watchAssignments('u-test').first).single;
        await repository.unassignCapital(assigned);
        await repository.assignWholeLot(
          lotId: 'lot-1',
          portfolioId: growth.id,
          rebalanceGroupId: growthGroup.id,
        );
        expect(
          (await repository.watchAssignments('u-test').first)
              .single
              .portfolioId,
          growth.id,
        );

        await repository.remove(growth);
        expect(
          (await repository.watchActive('u-test').first).single.id,
          income.id,
        );
        expect(await repository.watchAssignments('u-test').first, isEmpty);
        expect(
          outbox.queued.map((operation) => operation.table),
          containsAll([
            InvestmentPortfolioRepository.portfoliosTable,
            InvestmentPortfolioRepository.groupsTable,
            InvestmentPortfolioRepository.strategiesTable,
            InvestmentPortfolioRepository.assignmentsTable,
          ]),
        );
      },
    );

    test('adds strategy groups and keeps aggregate weights at 100%', () async {
      final db = makeTestDatabase();
      final repository = InvestmentPortfolioRepository(
        db: db,
        outbox: InMemoryOutboxStore(),
        stamper: makeStubStamper(),
      );
      addTearDown(db.close);
      final portfolio = await repository.create(
        name: 'Layered',
        initialStrategyKind: PortfolioStrategyKind.indexCore,
      );

      final dividend = await repository.addCapitalStrategy(
        portfolioId: portfolio.id,
        kind: PortfolioStrategyKind.dividendIncome,
      );
      var groups = await repository.watchGroups('u-test').first;
      expect(groups.map((group) => group.targetWeightBps), [5000, 5000]);

      await repository.setGroupTargetWeight(
        portfolioId: portfolio.id,
        groupId: dividend.id,
        targetWeightBps: 3000,
      );
      groups = await repository.watchGroups('u-test').first;
      expect(
        groups.fold<int>(0, (sum, group) => sum + group.targetWeightBps),
        10000,
      );
      expect(
        groups.singleWhere((group) => group.id == dividend.id).targetWeightBps,
        3000,
      );
    });

    test('assigns cash directly to a capital-owning group', () async {
      final db = makeTestDatabase();
      final repository = InvestmentPortfolioRepository(
        db: db,
        outbox: InMemoryOutboxStore(),
        stamper: makeStubStamper(),
      );
      addTearDown(db.close);
      final portfolio = await repository.create(
        name: 'Options',
        initialStrategyKind: PortfolioStrategyKind.optionsIncome,
      );
      final group = (await repository.watchGroups('u-test').first).single;

      await repository.assignCash(
        accountId: 'broker-cash',
        amount: Decimal.parse('25000'),
        currency: 'usd',
        portfolioId: portfolio.id,
        rebalanceGroupId: group.id,
      );

      final assignment =
          (await repository.watchAssignments('u-test').first).single;
      expect(assignment.sourceKind, PortfolioCapitalSourceKind.cashAccount);
      expect(assignment.sourceId, 'broker-cash');
      expect(assignment.amount, Decimal.parse('25000'));
      expect(assignment.currency, 'USD');
      expect(assignment.rebalanceGroupId, group.id);
    });

    test('persists target allocation on the selected group', () async {
      final db = makeTestDatabase();
      final repository = InvestmentPortfolioRepository(
        db: db,
        outbox: InMemoryOutboxStore(),
        stamper: makeStubStamper(),
      );
      addTearDown(db.close);
      final portfolio = await repository.create(
        name: 'Income',
        initialStrategyKind: PortfolioStrategyKind.dividendIncome,
      );
      final group = (await repository.watchGroups('u-test').first).single;
      final controller = TargetAllocationController(
        scheme: AllocationSchemePreset.balanced,
        group: group,
        repository: Future.value(repository),
      );
      addTearDown(controller.dispose);
      const target = TargetAllocation(
        weights: {
          AssetCategory.stock: 0.4,
          AssetCategory.etf: 0.3,
          AssetCategory.bondsAndFunds: 0.2,
          AssetCategory.cash: 0.1,
        },
      );

      await controller.update(target);

      final saved = (await repository.watchGroups('u-test').first).singleWhere(
        (candidate) => candidate.portfolioId == portfolio.id,
      );
      expect(saved.internalTarget.weights, target.weights);
    });

    test('persists target allocation for a virtual portfolio', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final preferences = await SharedPreferences.getInstance();
      final db = makeTestDatabase();
      final repository = InvestmentPortfolioRepository(
        db: db,
        outbox: InMemoryOutboxStore(),
        stamper: makeStubStamper(),
      );
      addTearDown(db.close);
      const storageKey = 'test.target-allocation.all';
      const target = TargetAllocation(
        weights: {
          AssetCategory.stock: 0.5,
          AssetCategory.etf: 0.2,
          AssetCategory.bondsAndFunds: 0.2,
          AssetCategory.cash: 0.1,
        },
      );
      final firstController = TargetAllocationController(
        scheme: AllocationSchemePreset.balanced,
        group: null,
        repository: Future.value(repository),
        preferences: preferences,
        virtualStorageKey: storageKey,
      );

      await firstController.update(target);
      firstController.dispose();

      final restartedController = TargetAllocationController(
        scheme: AllocationSchemePreset.custom,
        group: null,
        repository: Future.value(repository),
        preferences: preferences,
        virtualStorageKey: storageKey,
      );
      addTearDown(restartedController.dispose);
      expect(restartedController.state.weights, target.weights);
    });
  });

  group('scopePortfolioHoldings', () {
    test('uses lot cost proportions instead of quantity for cost basis', () {
      final scoped = scopePortfolioHoldings(
        snapshots: {
          'aapl': _holding(
            assetId: 'aapl',
            quantity: '10',
            cost: '1040',
            market: '1500',
          ),
        },
        lots: [
          _lot(id: 'cheap', assetId: 'aapl', quantity: '4', cost: '80'),
          _lot(id: 'expensive', assetId: 'aapl', quantity: '6', cost: '120'),
        ],
        assignments: [
          _assignment(
            id: 'a1',
            lotId: 'cheap',
            portfolioId: 'portfolio',
            groupId: 'income',
          ),
        ],
        selectedPortfolioId: 'portfolio',
      );

      expect(scoped.snapshots['aapl']!.quantity, Decimal.parse('4'));
      expect(
        scoped.snapshots['aapl']!.costBasisInBase.toDouble(),
        closeTo(320, 0.000001),
      );
      expect(
        scoped.snapshots['aapl']!.marketValueInBase,
        Decimal.parse('600.0'),
      );
    });

    test('partitions whole and partial lots by group', () {
      final aapl = _holding(
        assetId: 'aapl',
        quantity: '10',
        cost: '1000',
        market: '1500',
      );
      final lots = [
        _lot(id: 'aapl-lot', assetId: 'aapl', quantity: '10', cost: '100'),
      ];
      final assignments = [
        _assignment(
          id: 'a1',
          lotId: 'aapl-lot',
          portfolioId: 'portfolio',
          groupId: 'income',
          quantity: '4',
        ),
        _assignment(
          id: 'a2',
          lotId: 'aapl-lot',
          portfolioId: 'portfolio',
          groupId: 'growth',
          quantity: '6',
        ),
      ];

      final scoped = scopePortfolioHoldings(
        snapshots: {'aapl': aapl},
        lots: lots,
        assignments: assignments,
        selectedPortfolioId: 'portfolio',
      );

      expect(scoped.snapshots['aapl']!.quantity, Decimal.parse('10'));
      expect(
        scoped.snapshotsByGroup['income']!['aapl']!.marketValueInBase,
        Decimal.parse('600.0'),
      );
      expect(
        scoped.snapshotsByGroup['growth']!['aapl']!.marketValueInBase,
        Decimal.parse('900.0'),
      );
    });

    test('unassigned view retains the unowned partial-lot remainder', () {
      final scoped = scopePortfolioHoldings(
        snapshots: {
          'aapl': _holding(
            assetId: 'aapl',
            quantity: '10',
            cost: '1000',
            market: '1500',
          ),
        },
        lots: [
          _lot(id: 'aapl-lot', assetId: 'aapl', quantity: '10', cost: '100'),
        ],
        assignments: [
          _assignment(
            id: 'a1',
            lotId: 'aapl-lot',
            portfolioId: 'income',
            groupId: 'dividends',
            quantity: '4',
          ),
        ],
        selectedPortfolioId: kUnassignedInvestmentPortfolioId,
      );

      expect(scoped.lots.single.remainingQuantity, Decimal.parse('6'));
      expect(scoped.snapshots['aapl']!.quantity, Decimal.parse('6'));
      expect(
        scoped.snapshots['aapl']!.marketValueInBase,
        Decimal.parse('900.0'),
      );
    });
  });
}

HoldingSnapshot _holding({
  required String assetId,
  required String quantity,
  required String cost,
  required String market,
}) {
  final parsedCost = Decimal.parse(cost);
  final parsedMarket = Decimal.parse(market);
  return HoldingSnapshot(
    assetId: assetId,
    quantity: Decimal.parse(quantity),
    costBasisInAssetCurrency: parsedCost,
    marketValueInAssetCurrency: parsedMarket,
    assetCurrency: 'USD',
    costBasisInBase: parsedCost,
    marketValueInBase: parsedMarket,
    unrealizedPnlInBase: parsedMarket - parsedCost,
    weight: Decimal.zero,
    baseCurrency: 'USD',
    asOf: DateTime.utc(2026, 7, 20),
  );
}

Lot _lot({
  required String id,
  required String assetId,
  required String quantity,
  required String cost,
}) {
  return Lot(
    id: id,
    openingTransactionId: 'tx-$id',
    accountId: 'broker',
    assetId: assetId,
    currency: 'USD',
    originalQuantity: Decimal.parse(quantity),
    remainingQuantity: Decimal.parse(quantity),
    costPerUnit: Decimal.parse(cost),
    openedAt: DateTime.utc(2026, 1, 1),
  );
}

PortfolioCapitalAssignment _assignment({
  required String id,
  required String lotId,
  required String portfolioId,
  required String groupId,
  String? quantity,
}) {
  return PortfolioCapitalAssignment(
    id: id,
    portfolioId: portfolioId,
    rebalanceGroupId: groupId,
    sourceKind: PortfolioCapitalSourceKind.lot,
    sourceId: lotId,
    quantity: quantity == null ? null : Decimal.parse(quantity),
    amount: null,
    currency: null,
    assignedAt: DateTime.utc(2026, 7, 20),
    sync: SyncMeta(
      ownerUserId: 'u-test',
      updatedAt: DateTime.utc(2026, 7, 20),
      updatedByDevice: 'test',
      hlc: Hlc.zero('test'),
    ),
  );
}
