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
import 'package:naviwealth/features/finance/investment/domain/models/portfolio_removal_failure.dart';
import 'package:naviwealth/features/finance/investment/domain/strategy/portfolio_strategy.dart';
import 'package:naviwealth/features/finance/investment/domain/strategy/portfolio_strategy_template.dart';
import 'package:naviwealth/features/finance/rebalance/data/rebalance_providers.dart';
import 'package:naviwealth/features/finance/rebalance/domain/portfolio_rebalance_group.dart';
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
          initialStrategy: kDividendIncomeStrategyTemplate,
          baseCurrency: 'USD',
          languageCode: 'en',
        );
        final growth = await repository.create(
          name: 'Growth',
          initialStrategy: kIndexCoreStrategyTemplate,
          baseCurrency: 'USD',
          languageCode: 'en',
        );
        expect(income.name, 'Dividend income');
        expect(await repository.watchActive('u-test').first, hasLength(2));
        final universe =
            (await repository.watchUniverses('u-test').first).single;
        final portfolioTargets = await repository
            .watchPortfolioTargets('u-test')
            .first;
        expect(universe.baseCurrency, 'USD');
        expect(
          portfolioTargets
              .singleWhere((target) => target.portfolioId == income.id)
              .targetWeightBps,
          10000,
        );
        expect(
          portfolioTargets
              .singleWhere((target) => target.portfolioId == growth.id)
              .targetWeightBps,
          0,
        );
        final incomeTarget = portfolioTargets.singleWhere(
          (target) => target.portfolioId == income.id,
        );
        final growthTarget = portfolioTargets.singleWhere(
          (target) => target.portfolioId == growth.id,
        );
        await repository.updatePortfolioPlan(
          universeId: universe.id,
          targets: [
            incomeTarget.copyWith(targetWeightBps: 7000),
            growthTarget.copyWith(targetWeightBps: 3000),
          ],
        );
        final updatedTargets = await repository
            .watchPortfolioTargets('u-test')
            .first;
        expect(
          updatedTargets
              .singleWhere((target) => target.portfolioId == income.id)
              .targetWeightBps,
          7000,
        );
        expect(
          updatedTargets
              .singleWhere((target) => target.portfolioId == growth.id)
              .targetWeightBps,
          3000,
        );

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
        final reassignmentHistory = await repository
            .watchAssignmentHistory('u-test')
            .first;
        expect(reassignmentHistory, hasLength(2));
        expect(
          reassignmentHistory.where((item) => item.isActive),
          hasLength(1),
        );
        expect(
          reassignmentHistory
              .where((item) => !item.isActive)
              .single
              .portfolioId,
          income.id,
        );

        await expectLater(
          repository.remove(growth),
          throwsA(
            isA<PortfolioRemovalException>().having(
              (error) => error.reason,
              'reason',
              PortfolioRemovalFailureReason.transferTargetRequired,
            ),
          ),
        );
        await repository.remove(
          growth,
          destinationPortfolioId: income.id,
          destinationGroupId: incomeGroup.id,
        );
        expect(
          (await repository.watchActive('u-test').first).single.id,
          income.id,
        );
        expect(
          (await repository.watchPortfolioTargets('u-test').first)
              .single
              .targetWeightBps,
          10000,
        );
        expect(
          (await repository.watchAssignments('u-test').first).single,
          isA<PortfolioCapitalAssignment>()
              .having(
                (assignment) => assignment.portfolioId,
                'portfolioId',
                income.id,
              )
              .having(
                (assignment) => assignment.rebalanceGroupId,
                'rebalanceGroupId',
                incomeGroup.id,
              ),
        );
        final transferHistory = await repository
            .watchAssignmentHistory('u-test')
            .first;
        expect(transferHistory, hasLength(3));
        expect(transferHistory.where((item) => item.isActive), hasLength(1));
        expect(
          transferHistory.where((item) => item.isActive).single.portfolioId,
          income.id,
        );
        expect(
          outbox.queued.map((operation) => operation.table),
          containsAll([
            portfoliosTable,
            universesTable,
            portfolioTargetsTable,
            groupsTable,
            strategiesTable,
            assignmentsTable,
          ]),
        );
      },
    );

    test('persists and instantiates a custom strategy template', () async {
      final db = makeTestDatabase();
      final repository = InvestmentPortfolioRepository(
        db: db,
        outbox: InMemoryOutboxStore(),
        stamper: makeStubStamper(),
      );
      addTearDown(db.close);

      final template = await repository.createCustomStrategyTemplate(
        name: 'Quality',
        languageCode: 'en',
        iconToken: 'sparkles',
        capitalRole: StrategyCapitalRole.owner,
        defaultInternalTarget: const TargetAllocation(
          weights: {AssetCategory.stock: 1},
        ),
        defaultDriftBandBps: 300,
        defaultTransferPolicy: GroupTransferPolicy.inflowsOnly,
      );
      final persisted =
          (await repository.watchCustomStrategyTemplates('u-test').first)
              .single;
      expect(persisted.kind, template.kind);
      expect(persisted.displayName('en'), 'Quality');
      final updated = await repository.updateCustomStrategyTemplate(
        template: persisted,
        name: 'Quality growth',
        languageCode: 'en',
        defaultInternalTarget: const TargetAllocation(
          weights: {AssetCategory.stock: 0.8, AssetCategory.cash: 0.2},
        ),
        defaultDriftBandBps: 400,
        defaultTransferPolicy: GroupTransferPolicy.bidirectional,
      );
      expect(updated.displayName('en'), 'Quality growth');
      expect(
        (await repository.watchCustomStrategyTemplates('u-test').first)
            .single
            .defaultDriftBandBps,
        400,
      );

      final portfolio = await repository.create(
        name: 'Quality portfolio',
        initialStrategy: updated,
        baseCurrency: 'USD',
        languageCode: 'en',
      );
      final group = (await repository.watchGroups('u-test').first).single;
      final strategy =
          (await repository.watchStrategies('u-test').first).single;
      expect(group.portfolioId, portfolio.id);
      expect(group.strategyKind, persisted.kind);
      expect(group.driftBandBps, 400);
      expect(group.transferPolicy, GroupTransferPolicy.bidirectional);
      expect(strategy.settings, isA<OpaquePortfolioStrategySettings>());

      await repository.archiveCustomStrategyTemplate(updated);
      expect(
        await repository.watchCustomStrategyTemplates('u-test').first,
        isEmpty,
      );
    });

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
        initialStrategy: kIndexCoreStrategyTemplate,
        baseCurrency: 'USD',
        languageCode: 'en',
      );
      final onlyGroup = (await repository.watchGroups('u-test').first).single;

      final dividend = await repository.addCapitalStrategy(
        portfolioId: portfolio.id,
        template: kDividendIncomeStrategyTemplate,
      );
      var groups = await repository.watchGroups('u-test').first;
      expect(
        groups.singleWhere((group) => group.id == onlyGroup.id).targetWeightBps,
        10000,
      );
      expect(
        groups.singleWhere((group) => group.id == dividend.id).targetWeightBps,
        0,
      );

      await repository.updateStrategyPlan(
        portfolioId: portfolio.id,
        groups: [
          groups
              .singleWhere((group) => group.id == onlyGroup.id)
              .copyWith(targetWeightBps: 7000),
          groups
              .singleWhere((group) => group.id == dividend.id)
              .copyWith(targetWeightBps: 3000),
        ],
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
      await expectLater(
        repository.updateStrategyPlan(
          portfolioId: portfolio.id,
          groups: [
            groups
                .singleWhere((group) => group.id == onlyGroup.id)
                .copyWith(targetWeightBps: 5000),
            groups
                .singleWhere((group) => group.id == dividend.id)
                .copyWith(targetWeightBps: 3000),
          ],
        ),
        throwsArgumentError,
      );

      final configured = groups.singleWhere((group) => group.id == dividend.id);
      await repository.updateGroup(configured.copyWith(name: 'Income target'));
      await repository.updateStrategyPlan(
        portfolioId: portfolio.id,
        groups: [
          groups
              .singleWhere((group) => group.id == onlyGroup.id)
              .copyWith(targetWeightBps: 5000),
          configured.copyWith(
            name: 'Income target',
            targetWeightBps: 5000,
            transferPolicy: GroupTransferPolicy.isolated,
          ),
        ],
      );
      groups = await repository.watchGroups('u-test').first;
      expect(groups.map((group) => group.targetWeightBps), [5000, 5000]);
      expect(
        groups.singleWhere((group) => group.id == dividend.id),
        isA<PortfolioRebalanceGroup>()
            .having((group) => group.name, 'name', 'Income target')
            .having(
              (group) => group.transferPolicy,
              'transferPolicy',
              GroupTransferPolicy.isolated,
            ),
      );
    });

    test(
      'transfers and removes a strategy aggregate while protecting valid plans',
      () async {
        final db = makeTestDatabase();
        final outbox = InMemoryOutboxStore();
        final repository = InvestmentPortfolioRepository(
          db: db,
          outbox: outbox,
          stamper: makeStubStamper(),
        );
        addTearDown(db.close);
        final portfolio = await repository.create(
          name: 'Layered',
          initialStrategy: kIndexCoreStrategyTemplate,
          baseCurrency: 'USD',
          languageCode: 'en',
        );
        final initialGroup =
            (await repository.watchGroups('u-test').first).single;

        await expectLater(
          repository.removeCapitalStrategy(initialGroup),
          throwsA(
            isA<PortfolioRemovalException>().having(
              (error) => error.reason,
              'reason',
              PortfolioRemovalFailureReason.lastCapitalStrategy,
            ),
          ),
        );

        final removableGroup = await repository.addCapitalStrategy(
          portfolioId: portfolio.id,
          template: kDividendIncomeStrategyTemplate,
        );
        var groups = await repository.watchGroups('u-test').first;
        await repository.updateStrategyPlan(
          portfolioId: portfolio.id,
          groups: [
            groups
                .singleWhere((group) => group.id == initialGroup.id)
                .copyWith(targetWeightBps: 5000),
            groups
                .singleWhere((group) => group.id == removableGroup.id)
                .copyWith(targetWeightBps: 5000),
          ],
        );
        await expectLater(
          repository.removeCapitalStrategy(removableGroup),
          throwsA(
            isA<PortfolioRemovalException>().having(
              (error) => error.reason,
              'reason',
              PortfolioRemovalFailureReason.transferTargetRequired,
            ),
          ),
        );

        final overlayTemplate = await repository.createCustomStrategyTemplate(
          name: 'Risk guard',
          languageCode: 'en',
          iconToken: 'shield',
          capitalRole: StrategyCapitalRole.overlay,
          defaultInternalTarget: const TargetAllocation(
            weights: {AssetCategory.cash: 1},
          ),
          defaultDriftBandBps: 500,
          defaultTransferPolicy: GroupTransferPolicy.isolated,
        );
        await repository.addStrategyOverlay(
          portfolioId: portfolio.id,
          rebalanceGroupId: removableGroup.id,
          template: overlayTemplate,
        );
        await repository.assignCash(
          accountId: 'broker-cash',
          amount: Decimal.parse('1000'),
          availableAmount: Decimal.parse('1000'),
          currency: 'USD',
          portfolioId: portfolio.id,
          rebalanceGroupId: removableGroup.id,
        );

        await repository.removeCapitalStrategy(
          removableGroup,
          destinationGroupId: initialGroup.id,
        );

        final remainingGroup =
            (await repository.watchGroups('u-test').first).single;
        expect(remainingGroup.id, initialGroup.id);
        expect(remainingGroup.targetWeightBps, 10000);
        expect(
          (await repository.watchStrategies('u-test').first).map(
            (strategy) => strategy.kind,
          ),
          [PortfolioStrategyKind.indexCore],
        );
        expect(
          (await repository.watchAssignments('u-test').first)
              .single
              .rebalanceGroupId,
          initialGroup.id,
        );
        expect(
          outbox.queued.map((operation) => operation.table),
          containsAll([groupsTable, strategiesTable, assignmentsTable]),
        );

        final readded = await repository.addCapitalStrategy(
          portfolioId: portfolio.id,
          template: kDividendIncomeStrategyTemplate,
        );
        final duplicate = await repository.addCapitalStrategy(
          portfolioId: portfolio.id,
          template: kDividendIncomeStrategyTemplate,
        );
        expect(readded.id, isNot(removableGroup.id));
        expect(duplicate.id, isNot(readded.id));
        expect(await repository.watchGroups('u-test').first, hasLength(3));
      },
    );

    test('removes an overlay without changing its host strategy', () async {
      final db = makeTestDatabase();
      final repository = InvestmentPortfolioRepository(
        db: db,
        outbox: InMemoryOutboxStore(),
        stamper: makeStubStamper(),
      );
      addTearDown(db.close);
      final portfolio = await repository.create(
        name: 'Core',
        initialStrategy: kIndexCoreStrategyTemplate,
        baseCurrency: 'USD',
        languageCode: 'en',
      );
      final group = (await repository.watchGroups('u-test').first).single;
      final overlayTemplate = await repository.createCustomStrategyTemplate(
        name: 'Guard',
        languageCode: 'en',
        iconToken: 'shield',
        capitalRole: StrategyCapitalRole.overlay,
        defaultInternalTarget: const TargetAllocation(
          weights: {AssetCategory.cash: 1},
        ),
        defaultDriftBandBps: 500,
        defaultTransferPolicy: GroupTransferPolicy.isolated,
      );
      final overlay = await repository.addStrategyOverlay(
        portfolioId: portfolio.id,
        rebalanceGroupId: group.id,
        template: overlayTemplate,
      );

      await repository.removeStrategyOverlay(overlay);
      final readded = await repository.addStrategyOverlay(
        portfolioId: portfolio.id,
        rebalanceGroupId: group.id,
        template: overlayTemplate,
      );

      final strategies = await repository.watchStrategies('u-test').first;
      expect(strategies, hasLength(2));
      expect(readded.id, isNot(overlay.id));
      expect(
        strategies.where(
          (strategy) => strategy.capitalRole == StrategyCapitalRole.owner,
        ),
        hasLength(1),
      );
      expect(await repository.watchGroups('u-test').first, hasLength(1));
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
        initialStrategy: kOptionsIncomeStrategyTemplate,
        baseCurrency: 'USD',
        languageCode: 'en',
      );
      final group = (await repository.watchGroups('u-test').first).single;

      await repository.assignCash(
        accountId: 'broker-cash',
        amount: Decimal.parse('25000'),
        availableAmount: Decimal.parse('25000'),
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

    test(
      'moves a capital assignment atomically and preserves history',
      () async {
        final db = makeTestDatabase();
        final outbox = InMemoryOutboxStore();
        final repository = InvestmentPortfolioRepository(
          db: db,
          outbox: outbox,
          stamper: makeStubStamper(),
        );
        addTearDown(db.close);
        final source = await repository.create(
          name: 'Source',
          initialStrategy: kIndexCoreStrategyTemplate,
          baseCurrency: 'USD',
          languageCode: 'en',
        );
        final target = await repository.create(
          name: 'Target',
          initialStrategy: kDividendIncomeStrategyTemplate,
          baseCurrency: 'USD',
          languageCode: 'en',
        );
        final groups = await repository.watchGroups('u-test').first;
        final sourceGroup = groups.singleWhere(
          (group) => group.portfolioId == source.id,
        );
        final targetGroup = groups.singleWhere(
          (group) => group.portfolioId == target.id,
        );
        final original = await repository.assignWholeLot(
          lotId: 'lot-1',
          portfolioId: source.id,
          rebalanceGroupId: sourceGroup.id,
        );

        final replacement = await repository.moveCapitalAssignment(
          assignment: original,
          portfolioId: target.id,
          rebalanceGroupId: targetGroup.id,
        );

        final active = await repository.watchAssignments('u-test').first;
        expect(active, hasLength(1));
        expect(active.single.id, replacement.id);
        expect(active.single.portfolioId, target.id);
        final history = await repository.watchAssignmentHistory('u-test').first;
        expect(history, hasLength(2));
        expect(
          history
              .singleWhere((assignment) => assignment.id == original.id)
              .unassignedAt,
          isNotNull,
        );
        expect(
          outbox.queued
              .where((operation) => operation.table == assignmentsTable)
              .length,
          3,
        );
      },
    );

    test('rejects partial lot and cash assignments beyond capacity', () async {
      final db = makeTestDatabase();
      final repository = InvestmentPortfolioRepository(
        db: db,
        outbox: InMemoryOutboxStore(),
        stamper: makeStubStamper(),
      );
      addTearDown(db.close);
      final portfolio = await repository.create(
        name: 'Core',
        initialStrategy: kIndexCoreStrategyTemplate,
        baseCurrency: 'USD',
        languageCode: 'en',
      );
      final group = (await repository.watchGroups('u-test').first).single;
      await repository.assignLotQuantity(
        lotId: 'lot-1',
        quantity: Decimal.parse('6'),
        availableQuantity: Decimal.parse('10'),
        portfolioId: portfolio.id,
        rebalanceGroupId: group.id,
      );
      await expectLater(
        repository.assignLotQuantity(
          lotId: 'lot-1',
          quantity: Decimal.parse('5'),
          availableQuantity: Decimal.parse('10'),
          portfolioId: portfolio.id,
          rebalanceGroupId: group.id,
        ),
        throwsStateError,
      );
      await repository.assignCash(
        accountId: 'cash-1',
        amount: Decimal.parse('60'),
        availableAmount: Decimal.parse('100'),
        currency: 'USD',
        portfolioId: portfolio.id,
        rebalanceGroupId: group.id,
      );
      await expectLater(
        repository.assignCash(
          accountId: 'cash-1',
          amount: Decimal.parse('50'),
          availableAmount: Decimal.parse('100'),
          currency: 'USD',
          portfolioId: portfolio.id,
          rebalanceGroupId: group.id,
        ),
        throwsStateError,
      );
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
        initialStrategy: kDividendIncomeStrategyTemplate,
        baseCurrency: 'USD',
        languageCode: 'en',
      );
      final group = (await repository.watchGroups('u-test').first).single;
      final controller = TargetAllocationController(
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
        group: null,
        repository: Future.value(repository),
        preferences: preferences,
        virtualStorageKey: storageKey,
      );

      await firstController.update(target);
      firstController.dispose();

      final restartedController = TargetAllocationController(
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
