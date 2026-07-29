import 'package:naviwealth/features/finance/home/domain/dashboard_models.dart';
import 'package:naviwealth/features/finance/investment/domain/models/investment_portfolio.dart';
import 'package:naviwealth/features/finance/investment/domain/models/portfolio_capital_assignment.dart';
import 'package:naviwealth/features/finance/investment/domain/strategy/portfolio_strategy.dart';
import 'package:naviwealth/features/finance/rebalance/domain/portfolio_rebalance_group.dart';
import 'package:naviwealth/features/finance/rebalance/domain/rebalance_universe.dart';

/// The single user-facing hierarchy behind portfolio setup and rebalancing.
///
/// Existing persistence entities remain deliberately hidden behind this
/// projection. UI code works with one tree instead of coordinating universes,
/// portfolio targets, rebalance groups, strategy configs, and assignments.
enum AllocationNodeType { plan, portfolio, sleeve, asset }

enum AllocationAssetKind { category, security }

class AllocationNode {
  const AllocationNode({
    required this.id,
    required this.parentId,
    required this.type,
    required this.name,
    required this.targetWeightBps,
    required this.driftBandBps,
    required this.transferPolicy,
    this.referenceId,
    this.assetKind,
    this.assetCategory,
  });

  final String id;
  final String? parentId;
  final AllocationNodeType type;
  final String name;
  final int targetWeightBps;
  final int driftBandBps;
  final GroupTransferPolicy transferPolicy;

  /// Stable id of the persisted portfolio, strategy group, or concrete asset.
  final String? referenceId;
  final AllocationAssetKind? assetKind;
  final AssetCategory? assetCategory;

  double get targetWeight => targetWeightBps / 10000;
}

class StrategyAttachment {
  const StrategyAttachment({
    required this.id,
    required this.sleeveId,
    required this.kind,
    required this.enabled,
    required this.isPrimary,
    required this.config,
  });

  final String id;
  final String sleeveId;
  final PortfolioStrategyKind kind;
  final bool enabled;
  final bool isPrimary;
  final PortfolioStrategyConfig config;
}

class CapitalInclusion {
  const CapitalInclusion({
    required this.id,
    required this.sleeveId,
    required this.assignment,
  });

  final String id;
  final String sleeveId;
  final PortfolioCapitalAssignment assignment;
}

class PortfolioAllocationTree {
  const PortfolioAllocationTree({
    required this.root,
    required this.nodes,
    required this.attachments,
    required this.inclusions,
  });

  final AllocationNode root;
  final List<AllocationNode> nodes;
  final List<StrategyAttachment> attachments;
  final List<CapitalInclusion> inclusions;

  List<AllocationNode> childrenOf(String nodeId) =>
      nodes.where((node) => node.parentId == nodeId).toList(growable: false);

  AllocationNode? nodeForReference(
    AllocationNodeType type,
    String referenceId,
  ) => nodes
      .where((node) => node.type == type && node.referenceId == referenceId)
      .firstOrNull;

  List<StrategyAttachment> attachmentsFor(String sleeveId) => attachments
      .where((attachment) => attachment.sleeveId == sleeveId)
      .toList(growable: false);

  List<CapitalInclusion> inclusionsFor(String sleeveId) => inclusions
      .where((inclusion) => inclusion.sleeveId == sleeveId)
      .toList(growable: false);

  static PortfolioAllocationTree compose({
    required RebalanceUniverse universe,
    required List<InvestmentPortfolio> portfolios,
    required List<PortfolioAllocationTarget> portfolioTargets,
    required List<PortfolioRebalanceGroup> groups,
    required List<PortfolioStrategyConfig> strategies,
    required List<PortfolioCapitalAssignment> assignments,
  }) {
    final root = AllocationNode(
      id: universe.id,
      parentId: null,
      type: AllocationNodeType.plan,
      name: universe.name,
      targetWeightBps: 10000,
      driftBandBps: 0,
      transferPolicy: GroupTransferPolicy.bidirectional,
      referenceId: universe.id,
    );
    final targetByPortfolioId = {
      for (final target in portfolioTargets) target.portfolioId: target,
    };
    final nodes = <AllocationNode>[root];
    final sleeveNodeIdByGroupId = <String, String>{};

    for (final portfolio in portfolios) {
      final target = targetByPortfolioId[portfolio.id];
      if (target == null) continue;
      final portfolioNodeId = 'portfolio:${portfolio.id}';
      nodes.add(
        AllocationNode(
          id: portfolioNodeId,
          parentId: root.id,
          type: AllocationNodeType.portfolio,
          name: portfolio.name,
          targetWeightBps: target.targetWeightBps,
          driftBandBps: target.driftBandBps,
          transferPolicy: target.transferPolicy,
          referenceId: portfolio.id,
        ),
      );
      for (final group in groups.where(
        (candidate) => candidate.portfolioId == portfolio.id,
      )) {
        final sleeveNodeId = 'sleeve:${group.id}';
        sleeveNodeIdByGroupId[group.id] = sleeveNodeId;
        nodes.add(
          AllocationNode(
            id: sleeveNodeId,
            parentId: portfolioNodeId,
            type: AllocationNodeType.sleeve,
            name: group.name,
            targetWeightBps: group.targetWeightBps,
            driftBandBps: group.driftBandBps,
            transferPolicy: group.transferPolicy,
            referenceId: group.id,
          ),
        );
        for (final entry in group.internalTarget.weights.entries) {
          if (entry.value <= 0) continue;
          nodes.add(
            AllocationNode(
              id: '$sleeveNodeId:category:${entry.key.name}',
              parentId: sleeveNodeId,
              type: AllocationNodeType.asset,
              name: entry.key.name,
              targetWeightBps: (entry.value * 10000).round(),
              driftBandBps: group.driftBandBps,
              transferPolicy: GroupTransferPolicy.isolated,
              referenceId: entry.key.name,
              assetKind: AllocationAssetKind.category,
              assetCategory: entry.key,
            ),
          );
        }
        for (final target in group.internalTarget.assetTargets.values) {
          if (target.weight <= 0) continue;
          nodes.add(
            AllocationNode(
              id: '$sleeveNodeId:asset:${target.assetId}',
              parentId: sleeveNodeId,
              type: AllocationNodeType.asset,
              name: target.label,
              targetWeightBps: (target.weight * 10000).round(),
              driftBandBps: group.driftBandBps,
              transferPolicy: GroupTransferPolicy.isolated,
              referenceId: target.assetId,
              assetKind: AllocationAssetKind.security,
              assetCategory: target.category,
            ),
          );
        }
      }
    }

    return PortfolioAllocationTree(
      root: root,
      nodes: List.unmodifiable(nodes),
      attachments: List.unmodifiable([
        for (final strategy in strategies)
          if (strategy.rebalanceGroupId case final groupId?)
            if (sleeveNodeIdByGroupId[groupId] case final sleeveId?)
              StrategyAttachment(
                id: strategy.id,
                sleeveId: sleeveId,
                kind: strategy.kind,
                enabled: strategy.enabled,
                isPrimary: strategy.capitalRole == StrategyCapitalRole.owner,
                config: strategy,
              ),
      ]),
      inclusions: List.unmodifiable([
        for (final assignment in assignments)
          if (sleeveNodeIdByGroupId[assignment.rebalanceGroupId]
              case final sleeveId?)
            CapitalInclusion(
              id: assignment.id,
              sleeveId: sleeveId,
              assignment: assignment,
            ),
      ]),
    );
  }
}
