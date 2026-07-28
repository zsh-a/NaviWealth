import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/finance/domain/fx/money.dart';
import 'package:naviwealth/features/finance/home/domain/dashboard_models.dart';
import 'package:naviwealth/features/finance/investment/domain/models/investment_portfolio.dart';
import 'package:naviwealth/features/finance/investment/domain/strategy/portfolio_strategy.dart';
import 'package:naviwealth/features/finance/rebalance/domain/hierarchical_rebalance_engine.dart';
import 'package:naviwealth/features/finance/rebalance/domain/portfolio_rebalance_group.dart';
import 'package:naviwealth/features/finance/rebalance/domain/rebalance_engine.dart';
import 'package:naviwealth/features/finance/rebalance/domain/rebalance_models.dart';
import 'package:naviwealth/features/finance/rebalance/domain/rebalance_universe.dart';
import 'package:naviwealth/features/finance/rebalance/domain/universe_rebalance_engine.dart';

void main() {
  const engine = UniverseRebalanceEngine(
    portfolioEngine: HierarchicalRebalanceEngine(
      internalEngine: RebalanceEngine(
        warningThreshold: 0.01,
        criticalThreshold: 0.10,
      ),
    ),
  );

  test('allocates portfolios before their strategy groups and assets', () {
    final core = _portfolio('core');
    final income = _portfolio('income');
    final coreGroup = _group(portfolioId: core.id, category: AssetCategory.etf);
    final incomeGroup = _group(
      portfolioId: income.id,
      category: AssetCategory.stock,
    );

    final plan = engine.compute(
      target: UniverseAllocationTarget(
        universe: RebalanceUniverse(
          id: 'universe',
          name: 'Investment capital',
          baseCurrency: 'USD',
          createdAt: _now,
          archived: false,
          sync: _sync,
        ),
        portfolios: [_portfolioTarget(core.id), _portfolioTarget(income.id)],
      ),
      portfoliosById: {core.id: core, income.id: income},
      groupsByPortfolio: {
        core.id: [coreGroup],
        income.id: [incomeGroup],
      },
      snapshotsByPortfolioGroup: {
        core.id: {coreGroup.id: _snapshot('800', AssetCategory.etf)},
        income.id: {incomeGroup.id: _snapshot('200', AssetCategory.stock)},
      },
    );

    expect(plan.capitalPlan.transfers, hasLength(1));
    expect(plan.capitalPlan.transfers.single.fromNodeId, core.id);
    expect(plan.capitalPlan.transfers.single.toNodeId, income.id);
    expect(
      plan.capitalPlan.transfers.single.amount.amount,
      Decimal.parse('300.00000000'),
    );
    expect(plan.portfolios, hasLength(2));
    expect(
      plan.portfolios.every(
        (portfolio) =>
            portfolio.strategyPlan.groups.single.internalPlan != null,
      ),
      isTrue,
    );
  });
}

final _now = DateTime.utc(2026, 7, 28);
final _sync = SyncMeta(
  ownerUserId: 'u-test',
  updatedAt: _now,
  updatedByDevice: 'test',
  hlc: Hlc.zero('test'),
);

InvestmentPortfolio _portfolio(String id) {
  return InvestmentPortfolio(
    id: id,
    name: id,
    baseCurrency: 'USD',
    goalId: null,
    color: null,
    createdAt: _now,
    archived: false,
    sync: _sync,
  );
}

PortfolioAllocationTarget _portfolioTarget(String portfolioId) {
  return PortfolioAllocationTarget(
    id: '$portfolioId-target',
    universeId: 'universe',
    portfolioId: portfolioId,
    targetWeightBps: 5000,
    driftBandBps: 0,
    transferPolicy: GroupTransferPolicy.bidirectional,
    sync: _sync,
  );
}

PortfolioRebalanceGroup _group({
  required String portfolioId,
  required AssetCategory category,
}) {
  return PortfolioRebalanceGroup(
    id: '$portfolioId-group',
    portfolioId: portfolioId,
    name: portfolioId,
    strategyKind: PortfolioStrategyKind.indexCore,
    targetWeightBps: 10000,
    driftBandBps: 0,
    transferPolicy: GroupTransferPolicy.bidirectional,
    internalTarget: TargetAllocation(weights: {category: 1}),
    createdAt: _now,
    archived: false,
    sync: _sync,
  );
}

DashboardSnapshot _snapshot(String amount, AssetCategory category) {
  final value = Decimal.parse(amount);
  final money = Money(value, 'USD');
  return DashboardSnapshot(
    asOf: _now,
    baseCurrency: 'USD',
    allocations: [
      CategoryAllocation(
        category: category,
        totalInBase: money,
        items: [
          CategoryItem(
            id: category.name,
            name: category.name,
            subtitle: null,
            valueInBase: money,
            nativeAmount: value,
            nativeCurrency: 'USD',
          ),
        ],
      ),
    ],
    totalAssets: money,
    totalLiabilities: Money.zero('USD'),
    netWorth: money,
  );
}
