import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/finance/home/domain/dashboard_models.dart';
import 'package:naviwealth/features/finance/investment/data/investment_portfolio_providers.dart';
import 'package:naviwealth/features/finance/investment/data/investment_portfolio_repository.dart';
import 'package:naviwealth/features/finance/investment/domain/models/holding_snapshot.dart';
import 'package:naviwealth/features/finance/investment/domain/models/investment_portfolio.dart';
import 'package:naviwealth/features/finance/investment/domain/models/lot.dart';
import 'package:naviwealth/features/finance/rebalance/data/rebalance_providers.dart';
import 'package:naviwealth/features/finance/rebalance/domain/allocation_schemes.dart';
import 'package:naviwealth/features/finance/rebalance/domain/rebalance_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/persistence/test_database.dart';
import '../../../../core/sync/_outbox_test_ext.dart';
import '../../data/repositories/_stub_stamper.dart';

void main() {
  group('InvestmentPortfolioRepository', () {
    test('creates portfolios and moves one lot between them', () async {
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
        strategy: InvestmentPortfolioStrategy.income,
        targetAnnualIncome: Decimal.parse('12000'),
      );
      final growth = await repository.create(
        name: 'Growth',
        strategy: InvestmentPortfolioStrategy.growth,
      );
      expect(income.name, 'Dividend income');
      expect(await repository.watchActive('u-test').first, hasLength(2));

      await repository.assignLot(lotId: 'lot-1', portfolioId: income.id);
      var memberships = await repository.watchMemberships('u-test').first;
      expect(memberships.single.portfolioId, income.id);

      await repository.assignLot(lotId: 'lot-1', portfolioId: growth.id);
      memberships = await repository.watchMemberships('u-test').first;
      expect(memberships, hasLength(1));
      expect(memberships.single.portfolioId, growth.id);

      await repository.remove(growth);
      final remaining = await repository.watchActive('u-test').first;
      expect(remaining.single.id, income.id);
      expect(await repository.watchMemberships('u-test').first, isEmpty);
      expect(
        outbox.queued.map((operation) => operation.table),
        containsAll([
          InvestmentPortfolioRepository.portfoliosTable,
          InvestmentPortfolioRepository.membershipsTable,
        ]),
      );
    });

    test('persists target allocation on the selected portfolio', () async {
      final db = makeTestDatabase();
      final repository = InvestmentPortfolioRepository(
        db: db,
        outbox: InMemoryOutboxStore(),
        stamper: makeStubStamper(),
      );
      addTearDown(db.close);
      final portfolio = await repository.create(
        name: 'Income',
        strategy: InvestmentPortfolioStrategy.income,
      );
      final controller = TargetAllocationController(
        scheme: AllocationSchemePreset.balanced,
        portfolio: portfolio,
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

      final saved = (await repository.watchActive('u-test').first).single;
      final decoded = TargetAllocation.fromJson(
        jsonDecode(saved.targetAllocationJson!) as Map<String, dynamic>,
      );
      expect(decoded.weights, target.weights);
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
        portfolio: null,
        repository: Future.value(repository),
        preferences: preferences,
        virtualStorageKey: storageKey,
      );

      await firstController.update(target);
      firstController.dispose();

      final restartedController = TargetAllocationController(
        scheme: AllocationSchemePreset.custom,
        portfolio: null,
        repository: Future.value(repository),
        preferences: preferences,
        virtualStorageKey: storageKey,
      );
      addTearDown(restartedController.dispose);
      expect(restartedController.state.weights, target.weights);
    });
  });

  group('scopePortfolioHoldings', () {
    test('uses lot quantity and cost proportions for one portfolio', () {
      final aapl = _holding(
        assetId: 'aapl',
        quantity: '10',
        cost: '1000',
        market: '1500',
      );
      final bond = _holding(
        assetId: 'bond',
        quantity: '5',
        cost: '500',
        market: '550',
      );
      final lots = [
        _lot(id: 'aapl-income', assetId: 'aapl', quantity: '4', cost: '100'),
        _lot(id: 'aapl-growth', assetId: 'aapl', quantity: '6', cost: '100'),
        _lot(id: 'bond-income', assetId: 'bond', quantity: '5', cost: '100'),
      ];
      final memberships = [
        _membership(lotId: 'aapl-income', portfolioId: 'income'),
        _membership(lotId: 'bond-income', portfolioId: 'income'),
      ];

      final scoped = scopePortfolioHoldings(
        snapshots: {'aapl': aapl, 'bond': bond},
        lots: lots,
        memberships: memberships,
        selectedPortfolioId: 'income',
      );

      expect(scoped.lots.map((lot) => lot.id), ['aapl-income', 'bond-income']);
      expect(scoped.snapshots['aapl']!.quantity, Decimal.parse('4'));
      expect(
        scoped.snapshots['aapl']!.marketValueInBase,
        Decimal.parse('600.0'),
      );
      expect(scoped.snapshots['aapl']!.costBasisInBase, Decimal.parse('400'));
      expect(scoped.snapshots['bond']!.marketValueInBase, Decimal.parse('550'));
      expect(
        scoped.snapshots.values
            .fold<Decimal>(Decimal.zero, (sum, holding) => sum + holding.weight)
            .toDouble(),
        closeTo(1, 0.00000002),
      );
    });

    test('unassigned view excludes every assigned lot', () {
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
          _lot(id: 'assigned', assetId: 'aapl', quantity: '4', cost: '100'),
          _lot(id: 'free', assetId: 'aapl', quantity: '6', cost: '100'),
        ],
        memberships: [_membership(lotId: 'assigned', portfolioId: 'income')],
        selectedPortfolioId: kUnassignedInvestmentPortfolioId,
      );

      expect(scoped.lots.single.id, 'free');
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

PortfolioLotMembership _membership({
  required String lotId,
  required String portfolioId,
}) {
  return PortfolioLotMembership(
    lotId: lotId,
    portfolioId: portfolioId,
    assignedAt: DateTime.utc(2026, 7, 20),
    sync: SyncMeta(
      ownerUserId: 'u-test',
      updatedAt: DateTime.utc(2026, 7, 20),
      updatedByDevice: 'test',
      hlc: Hlc.zero('test'),
    ),
  );
}
