import 'package:decimal/decimal.dart';
import 'package:naviwealth/features/finance/domain/fx/money.dart';
import 'package:naviwealth/features/finance/home/domain/dashboard_models.dart';

import 'capital_allocation_engine.dart';
import 'portfolio_rebalance_group.dart';
import 'rebalance_engine.dart';
import 'rebalance_models.dart';

/// Why a group did or did not participate in portfolio-level capital movement.
enum GroupCapitalAction {
  transferIn,
  transferOut,
  withinBand,
  policyBlocked,
  noCounterparty,
}

class GroupCapitalDecision {
  const GroupCapitalDecision({
    required this.groupId,
    required this.groupName,
    required this.actualWeight,
    required this.targetWeight,
    required this.actualAmount,
    required this.targetAmount,
    required this.action,
    required this.explanation,
  });

  final String groupId;
  final String groupName;
  final double actualWeight;
  final double targetWeight;
  final Money actualAmount;
  final Money targetAmount;
  final GroupCapitalAction action;
  final String explanation;

  double get deviation => actualWeight - targetWeight;
}

class GroupCapitalTransfer {
  const GroupCapitalTransfer({
    required this.fromGroupId,
    required this.toGroupId,
    required this.amount,
    required this.explanation,
  });

  final String fromGroupId;
  final String toGroupId;
  final Money amount;
  final String explanation;
}

class GroupRebalancePlan {
  const GroupRebalancePlan({
    required this.group,
    required this.capitalDecision,
    required this.internalPlan,
  });

  final PortfolioRebalanceGroup group;
  final GroupCapitalDecision capitalDecision;
  final RebalancePlan? internalPlan;
}

/// Explainable two-stage plan.
///
/// [transfers] moves capital between exclusive owners first. Each
/// [GroupRebalancePlan.internalPlan] then rebalances only the holdings owned by
/// that group. Strategy overlays never enter this calculation.
class PortfolioRebalancePlan {
  const PortfolioRebalancePlan({
    required this.totalAssets,
    required this.groups,
    required this.transfers,
  });

  final Money totalAssets;
  final List<GroupRebalancePlan> groups;
  final List<GroupCapitalTransfer> transfers;

  bool get requiresAction =>
      transfers.isNotEmpty ||
      groups.any((group) => !(group.internalPlan?.isBalanced ?? true));
}

class HierarchicalRebalanceEngine {
  const HierarchicalRebalanceEngine({
    required this.internalEngine,
    this.capitalEngine = const CapitalAllocationEngine(),
  });

  final RebalanceEngine internalEngine;
  final CapitalAllocationEngine capitalEngine;

  PortfolioRebalancePlan compute({
    required PortfolioRebalanceTarget target,
    required Map<String, DashboardSnapshot> snapshotsByGroup,
    required String baseCurrency,
  }) {
    if (!target.isValid) {
      throw const FormatException(
        'Portfolio rebalance group weights must sum to 10000 basis points.',
      );
    }
    final capitalPlan = capitalEngine.compute(
      baseCurrency: baseCurrency,
      nodes: [
        for (final group in target.groups)
          CapitalAllocationNode(
            id: group.id,
            name: group.name,
            targetWeightBps: group.targetWeightBps,
            driftBandBps: group.driftBandBps,
            transferPolicy: group.transferPolicy,
            actualAmount:
                snapshotsByGroup[group.id]?.totalAssets.amount ?? Decimal.zero,
          ),
      ],
    );
    final transfers = [
      for (final transfer in capitalPlan.transfers)
        GroupCapitalTransfer(
          fromGroupId: transfer.fromNodeId,
          toGroupId: transfer.toNodeId,
          amount: transfer.amount,
          explanation: transfer.explanation,
        ),
    ];
    return PortfolioRebalancePlan(
      totalAssets: capitalPlan.totalAssets,
      transfers: List.unmodifiable(transfers),
      groups: List.unmodifiable([
        for (final group in target.groups)
          GroupRebalancePlan(
            group: group,
            capitalDecision: _groupDecision(capitalPlan.decisions[group.id]!),
            internalPlan: _internalPlan(
              snapshotsByGroup[group.id],
              group.internalTarget,
            ),
          ),
      ]),
    );
  }

  RebalancePlan? _internalPlan(
    DashboardSnapshot? snapshot,
    TargetAllocation target,
  ) {
    if (snapshot == null || snapshot.isEmpty) return null;
    return internalEngine.compute(snapshot: snapshot, target: target);
  }

  GroupCapitalDecision _groupDecision(CapitalAllocationDecision decision) {
    return GroupCapitalDecision(
      groupId: decision.nodeId,
      groupName: decision.nodeName,
      actualWeight: decision.actualWeight,
      targetWeight: decision.targetWeight,
      actualAmount: decision.actualAmount,
      targetAmount: decision.targetAmount,
      action: GroupCapitalAction.values.byName(decision.action.name),
      explanation: decision.explanation,
    );
  }
}
