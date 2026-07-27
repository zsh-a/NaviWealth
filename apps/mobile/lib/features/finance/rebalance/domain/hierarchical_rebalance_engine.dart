import 'package:decimal/decimal.dart';
import 'package:naviwealth/features/finance/domain/fx/money.dart';
import 'package:naviwealth/features/finance/home/domain/dashboard_models.dart';

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
  const HierarchicalRebalanceEngine({required this.internalEngine});

  final RebalanceEngine internalEngine;

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
    final total = target.groups.fold<Decimal>(
      Decimal.zero,
      (sum, group) =>
          sum +
          (snapshotsByGroup[group.id]?.totalAssets.amount ?? Decimal.zero),
    );
    final totalAssets = Money(total, baseCurrency);
    final states = [
      for (final group in target.groups)
        _GroupState(
          group: group,
          actual:
              snapshotsByGroup[group.id]?.totalAssets.amount ?? Decimal.zero,
          portfolioTotal: total,
          target:
              (total *
                      Decimal.fromInt(group.targetWeightBps) /
                      Decimal.fromInt(10000))
                  .toDecimal(scaleOnInfinitePrecision: 8),
        ),
    ];
    final transfers = _matchTransfers(states, baseCurrency);
    final decisions = _decisions(states, transfers, totalAssets);
    return PortfolioRebalancePlan(
      totalAssets: totalAssets,
      transfers: List.unmodifiable(transfers),
      groups: List.unmodifiable([
        for (final state in states)
          GroupRebalancePlan(
            group: state.group,
            capitalDecision: decisions[state.group.id]!,
            internalPlan: _internalPlan(
              snapshotsByGroup[state.group.id],
              state.group.internalTarget,
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

  List<GroupCapitalTransfer> _matchTransfers(
    List<_GroupState> states,
    String currency,
  ) {
    final sources = [
      for (final state in states)
        if (state.transferableSurplus > Decimal.zero)
          _MutableAmount(state, state.transferableSurplus),
    ];
    final destinations = [
      for (final state in states)
        if (state.acceptableDeficit > Decimal.zero)
          _MutableAmount(state, state.acceptableDeficit),
    ];
    final transfers = <GroupCapitalTransfer>[];
    var sourceIndex = 0;
    var destinationIndex = 0;
    while (sourceIndex < sources.length &&
        destinationIndex < destinations.length) {
      final source = sources[sourceIndex];
      final destination = destinations[destinationIndex];
      final amount = source.remaining < destination.remaining
          ? source.remaining
          : destination.remaining;
      if (amount > Decimal.zero) {
        transfers.add(
          GroupCapitalTransfer(
            fromGroupId: source.state.group.id,
            toGroupId: destination.state.group.id,
            amount: Money(amount, currency),
            explanation:
                '${source.state.group.name} exceeds its target outside the '
                'drift band; ${destination.state.group.name} is below target.',
          ),
        );
        source.remaining -= amount;
        destination.remaining -= amount;
      }
      if (source.remaining <= Decimal.zero) sourceIndex += 1;
      if (destination.remaining <= Decimal.zero) destinationIndex += 1;
    }
    return transfers;
  }

  Map<String, GroupCapitalDecision> _decisions(
    List<_GroupState> states,
    List<GroupCapitalTransfer> transfers,
    Money totalAssets,
  ) {
    return {
      for (final state in states)
        state.group.id: _decision(state, transfers, totalAssets),
    };
  }

  GroupCapitalDecision _decision(
    _GroupState state,
    List<GroupCapitalTransfer> transfers,
    Money totalAssets,
  ) {
    final outgoing = transfers.any(
      (transfer) => transfer.fromGroupId == state.group.id,
    );
    final incoming = transfers.any(
      (transfer) => transfer.toGroupId == state.group.id,
    );
    final action = switch ((outgoing, incoming)) {
      (true, _) => GroupCapitalAction.transferOut,
      (_, true) => GroupCapitalAction.transferIn,
      _ when state.withinBand => GroupCapitalAction.withinBand,
      _ when state.policyBlocksRequiredTransfer =>
        GroupCapitalAction.policyBlocked,
      _ => GroupCapitalAction.noCounterparty,
    };
    final explanation = switch (action) {
      GroupCapitalAction.transferOut =>
        'Above target; policy allows capital to leave this group.',
      GroupCapitalAction.transferIn =>
        'Below target; policy allows capital to enter this group.',
      GroupCapitalAction.withinBand =>
        'Group weight is inside its configured drift band.',
      GroupCapitalAction.policyBlocked =>
        'The transfer policy intentionally blocks the required movement.',
      GroupCapitalAction.noCounterparty =>
        'Outside the drift band, but no eligible counterparty can fund it.',
    };
    final total = totalAssets.amount.toDouble();
    return GroupCapitalDecision(
      groupId: state.group.id,
      groupName: state.group.name,
      actualWeight: total <= 0 ? 0 : state.actual.toDouble() / total,
      targetWeight: state.group.targetWeightBps / 10000,
      actualAmount: Money(state.actual, totalAssets.currency),
      targetAmount: Money(state.target, totalAssets.currency),
      action: action,
      explanation: explanation,
    );
  }
}

class _GroupState {
  const _GroupState({
    required this.group,
    required this.actual,
    required this.portfolioTotal,
    required this.target,
  });

  final PortfolioRebalanceGroup group;
  final Decimal actual;
  final Decimal portfolioTotal;
  final Decimal target;

  Decimal get deviation => actual - target;

  Decimal get bandAmount =>
      (portfolioTotal *
              Decimal.fromInt(group.driftBandBps) /
              Decimal.fromInt(10000))
          .toDecimal(scaleOnInfinitePrecision: 8);

  bool get withinBand => deviation.abs() <= bandAmount;

  Decimal get transferableSurplus {
    if (withinBand ||
        deviation <= Decimal.zero ||
        group.transferPolicy != GroupTransferPolicy.bidirectional) {
      return Decimal.zero;
    }
    return deviation;
  }

  Decimal get acceptableDeficit {
    if (withinBand ||
        deviation >= Decimal.zero ||
        group.transferPolicy == GroupTransferPolicy.isolated) {
      return Decimal.zero;
    }
    return -deviation;
  }

  bool get policyBlocksRequiredTransfer {
    if (withinBand) return false;
    if (deviation > Decimal.zero) {
      return group.transferPolicy != GroupTransferPolicy.bidirectional;
    }
    return group.transferPolicy == GroupTransferPolicy.isolated;
  }
}

class _MutableAmount {
  _MutableAmount(this.state, this.remaining);

  final _GroupState state;
  Decimal remaining;
}
