import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/finance/home/domain/dashboard_models.dart';
import 'package:naviwealth/features/finance/investment/domain/allocation/portfolio_allocation_tree.dart';
import 'package:naviwealth/features/finance/investment/domain/models/investment_portfolio.dart';
import 'package:naviwealth/features/finance/investment/domain/models/portfolio_capital_assignment.dart';
import 'package:naviwealth/features/finance/investment/domain/strategy/portfolio_strategy.dart';
import 'package:naviwealth/features/finance/rebalance/domain/portfolio_rebalance_group.dart';
import 'package:naviwealth/features/finance/rebalance/domain/rebalance_models.dart';
import 'package:naviwealth/features/finance/rebalance/domain/rebalance_universe.dart';

void main() {
  final now = DateTime.utc(2026);
  final sync = SyncMeta(
    ownerUserId: 'owner',
    updatedAt: now,
    updatedByDevice: 'device',
    hlc: const Hlc(wallMillis: 1, counter: 0, nodeId: 'device'),
  );

  test('composes plan, portfolio, sleeve, assets, rules, and inclusions', () {
    final portfolio = InvestmentPortfolio(
      id: 'portfolio-1',
      name: 'Long term',
      baseCurrency: 'USD',
      goalId: null,
      color: null,
      createdAt: now,
      archived: false,
      sync: sync,
    );
    final group = PortfolioRebalanceGroup(
      id: 'sleeve-1',
      portfolioId: 'portfolio-1',
      name: 'Index core',
      strategyKind: PortfolioStrategyKind.indexCore,
      targetWeightBps: 10000,
      driftBandBps: 500,
      transferPolicy: GroupTransferPolicy.bidirectional,
      internalTarget: const TargetAllocation(
        weights: {AssetCategory.stock: 0.8},
        assetTargets: {
          'BND': AssetTargetAllocation(
            assetId: 'BND',
            label: 'Bond ETF',
            category: AssetCategory.bondsAndFunds,
            weight: 0.2,
          ),
        },
      ),
      createdAt: now,
      archived: false,
      sync: sync,
    );
    final primary = PortfolioStrategyConfig(
      id: 'strategy-1',
      portfolioId: 'portfolio-1',
      kind: PortfolioStrategyKind.indexCore,
      schemaVersion: 1,
      enabled: true,
      capitalRole: StrategyCapitalRole.owner,
      rebalanceGroupId: 'sleeve-1',
      settings: const IndexCoreStrategySettings(automaticContributions: true),
      sync: sync,
    );
    final rule = PortfolioStrategyConfig(
      id: 'rule-1',
      portfolioId: 'portfolio-1',
      kind: PortfolioStrategyKind.optionsIncome,
      schemaVersion: 1,
      enabled: true,
      capitalRole: StrategyCapitalRole.overlay,
      rebalanceGroupId: 'sleeve-1',
      settings: const OptionsIncomeStrategySettings(
        protectCollateral: true,
        useOwnerProfile: true,
      ),
      sync: sync,
    );
    final assignment = PortfolioCapitalAssignment(
      id: 'inclusion-1',
      portfolioId: 'portfolio-1',
      rebalanceGroupId: 'sleeve-1',
      sourceKind: PortfolioCapitalSourceKind.lot,
      sourceId: 'lot-1',
      quantity: null,
      amount: null,
      currency: null,
      assignedAt: now,
      sync: sync,
    );

    final tree = PortfolioAllocationTree.compose(
      universe: RebalanceUniverse(
        id: 'plan-1',
        name: 'Investment plan',
        baseCurrency: 'USD',
        createdAt: now,
        archived: false,
        sync: sync,
      ),
      portfolios: [portfolio],
      portfolioTargets: [
        PortfolioAllocationTarget(
          id: 'target-1',
          universeId: 'plan-1',
          portfolioId: 'portfolio-1',
          targetWeightBps: 10000,
          driftBandBps: 500,
          transferPolicy: GroupTransferPolicy.bidirectional,
          sync: sync,
        ),
      ],
      groups: [group],
      strategies: [primary, rule],
      assignments: [assignment],
    );

    final portfolioNode = tree.nodeForReference(
      AllocationNodeType.portfolio,
      portfolio.id,
    );
    expect(portfolioNode, isNotNull);
    final sleeves = tree.childrenOf(portfolioNode!.id);
    expect(sleeves, hasLength(1));
    expect(sleeves.single.name, 'Index core');
    expect(identical(sleeves, tree.childrenOf(portfolioNode.id)), isTrue);
    expect(() => sleeves.clear(), throwsUnsupportedError);

    final assetNodes = tree.childrenOf(sleeves.single.id);
    expect(assetNodes, hasLength(2));
    expect(
      assetNodes.fold<int>(0, (sum, node) => sum + node.targetWeightBps),
      10000,
    );
    expect(
      assetNodes.where(
        (node) => node.assetKind == AllocationAssetKind.security,
      ),
      hasLength(1),
    );

    final attachments = tree.attachmentsFor(sleeves.single.id);
    expect(attachments, hasLength(2));
    expect(
      identical(attachments, tree.attachmentsFor(sleeves.single.id)),
      isTrue,
    );
    expect(attachments.where((item) => item.isPrimary), hasLength(1));
    expect(attachments.where((item) => !item.isPrimary), hasLength(1));
    final inclusions = tree.inclusionsFor(sleeves.single.id);
    expect(inclusions.single.id, assignment.id);
    expect(
      identical(inclusions, tree.inclusionsFor(sleeves.single.id)),
      isTrue,
    );
  });

  test('freezes constructor inputs and preserves first reference match', () {
    const root = AllocationNode(
      id: 'plan',
      parentId: null,
      type: AllocationNodeType.plan,
      name: 'Plan',
      targetWeightBps: 10000,
      driftBandBps: 0,
      transferPolicy: GroupTransferPolicy.bidirectional,
    );
    const first = AllocationNode(
      id: 'portfolio:first',
      parentId: 'plan',
      type: AllocationNodeType.portfolio,
      name: 'First',
      targetWeightBps: 5000,
      driftBandBps: 500,
      transferPolicy: GroupTransferPolicy.bidirectional,
      referenceId: 'shared',
    );
    const second = AllocationNode(
      id: 'portfolio:second',
      parentId: 'plan',
      type: AllocationNodeType.portfolio,
      name: 'Second',
      targetWeightBps: 5000,
      driftBandBps: 500,
      transferPolicy: GroupTransferPolicy.bidirectional,
      referenceId: 'shared',
    );
    final sourceNodes = <AllocationNode>[root, first, second];
    final tree = PortfolioAllocationTree(
      root: root,
      nodes: sourceNodes,
      attachments: const [],
      inclusions: const [],
    );

    sourceNodes.clear();

    expect(tree.childrenOf(root.id), [first, second]);
    expect(
      tree.nodeForReference(AllocationNodeType.portfolio, 'shared'),
      same(first),
    );
    expect(tree.childrenOf('missing'), isEmpty);
    expect(tree.attachmentsFor('missing'), isEmpty);
    expect(tree.inclusionsFor('missing'), isEmpty);
  });

  test('omits portfolios without an active plan target', () {
    final tree = PortfolioAllocationTree.compose(
      universe: RebalanceUniverse(
        id: 'plan-1',
        name: 'Investment plan',
        baseCurrency: 'USD',
        createdAt: now,
        archived: false,
        sync: sync,
      ),
      portfolios: [
        InvestmentPortfolio(
          id: 'orphan',
          name: 'Orphan',
          baseCurrency: 'USD',
          goalId: null,
          color: null,
          createdAt: now,
          archived: false,
          sync: sync,
        ),
      ],
      portfolioTargets: const [],
      groups: const [],
      strategies: const [],
      assignments: const [],
    );

    expect(tree.childrenOf(tree.root.id), isEmpty);
  });
}
