import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/finance/domain/fx/money.dart';
import 'package:naviwealth/features/finance/home/domain/dashboard_models.dart';
import 'package:naviwealth/features/finance/investment/domain/strategy/portfolio_strategy.dart';
import 'package:naviwealth/features/finance/rebalance/domain/hierarchical_rebalance_engine.dart';
import 'package:naviwealth/features/finance/rebalance/domain/portfolio_rebalance_group.dart';
import 'package:naviwealth/features/finance/rebalance/domain/rebalance_engine.dart';
import 'package:naviwealth/features/finance/rebalance/domain/rebalance_models.dart';

void main() {
  const engine = HierarchicalRebalanceEngine(
    internalEngine: RebalanceEngine(
      warningThreshold: 0.01,
      criticalThreshold: 0.10,
    ),
  );

  test('matches group capital before computing independent internal plans', () {
    final index = _group(
      id: 'index',
      weightBps: 6000,
      policy: GroupTransferPolicy.bidirectional,
      target: const TargetAllocation(weights: {AssetCategory.etf: 1}),
    );
    final dividends = _group(
      id: 'dividends',
      weightBps: 4000,
      policy: GroupTransferPolicy.inflowsOnly,
      target: const TargetAllocation(weights: {AssetCategory.stock: 1}),
    );

    final plan = engine.compute(
      target: PortfolioRebalanceTarget(groups: [index, dividends]),
      snapshotsByGroup: {
        index.id: _snapshot(
          amount: '800',
          category: AssetCategory.etf,
          itemId: 'spy',
        ),
        dividends.id: _snapshot(
          amount: '200',
          category: AssetCategory.stock,
          itemId: 'jnj',
        ),
      },
      baseCurrency: 'USD',
    );

    expect(plan.totalAssets.amount, Decimal.parse('1000'));
    expect(plan.transfers, hasLength(1));
    expect(plan.transfers.single.fromGroupId, index.id);
    expect(plan.transfers.single.toGroupId, dividends.id);
    expect(plan.transfers.single.amount.amount, Decimal.parse('200.00000000'));
    expect(plan.groups, hasLength(2));
    expect(plan.groups.every((group) => group.internalPlan != null), isTrue);
  });

  test('isolated group explains a blocked transfer', () {
    final core = _group(
      id: 'core',
      weightBps: 5000,
      policy: GroupTransferPolicy.bidirectional,
      target: const TargetAllocation(weights: {AssetCategory.etf: 1}),
    );
    final options = _group(
      id: 'options',
      weightBps: 5000,
      policy: GroupTransferPolicy.isolated,
      target: const TargetAllocation(weights: {AssetCategory.cash: 1}),
    );

    final plan = engine.compute(
      target: PortfolioRebalanceTarget(groups: [core, options]),
      snapshotsByGroup: {
        core.id: _snapshot(
          amount: '800',
          category: AssetCategory.etf,
          itemId: 'spy',
        ),
        options.id: _snapshot(
          amount: '200',
          category: AssetCategory.cash,
          itemId: 'cash',
        ),
      },
      baseCurrency: 'USD',
    );

    expect(plan.transfers, isEmpty);
    expect(
      plan.groups
          .singleWhere((group) => group.group.id == options.id)
          .capitalDecision
          .action,
      GroupCapitalAction.policyBlocked,
    );
  });

  test('rejects group targets that do not sum to 100%', () {
    final invalid = _group(
      id: 'invalid',
      weightBps: 9000,
      policy: GroupTransferPolicy.bidirectional,
      target: const TargetAllocation(weights: {AssetCategory.etf: 1}),
    );

    expect(
      () => engine.compute(
        target: PortfolioRebalanceTarget(groups: [invalid]),
        snapshotsByGroup: const {},
        baseCurrency: 'USD',
      ),
      throwsFormatException,
    );
  });
}

PortfolioRebalanceGroup _group({
  required String id,
  required int weightBps,
  required GroupTransferPolicy policy,
  required TargetAllocation target,
}) {
  return PortfolioRebalanceGroup(
    id: id,
    portfolioId: 'portfolio',
    name: id,
    strategyKind: PortfolioStrategyKind.indexCore,
    targetWeightBps: weightBps,
    driftBandBps: 500,
    transferPolicy: policy,
    internalTarget: target,
    createdAt: DateTime.utc(2026, 7, 20),
    archived: false,
    sync: SyncMeta(
      ownerUserId: 'u-test',
      updatedAt: DateTime.utc(2026, 7, 20),
      updatedByDevice: 'test',
      hlc: Hlc.zero('test'),
    ),
  );
}

DashboardSnapshot _snapshot({
  required String amount,
  required AssetCategory category,
  required String itemId,
}) {
  final value = Decimal.parse(amount);
  final money = Money(value, 'USD');
  return DashboardSnapshot(
    asOf: DateTime.utc(2026, 7, 20),
    baseCurrency: 'USD',
    allocations: [
      CategoryAllocation(
        category: category,
        totalInBase: money,
        items: [
          CategoryItem(
            id: itemId,
            name: itemId,
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
