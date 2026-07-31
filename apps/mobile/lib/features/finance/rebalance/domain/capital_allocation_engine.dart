import 'package:decimal/decimal.dart';
import 'package:naviwealth/features/finance/domain/fx/money.dart';

import 'portfolio_rebalance_group.dart';

/// One capital-owning child in any level of the allocation tree.
class CapitalAllocationNode {
  const CapitalAllocationNode({
    required this.id,
    required this.name,
    required this.targetWeightBps,
    required this.driftBandBps,
    required this.transferPolicy,
    required this.actualAmount,
  });

  final String id;
  final String name;
  final int targetWeightBps;
  final int driftBandBps;
  final GroupTransferPolicy transferPolicy;
  final Decimal actualAmount;

  bool get isValid =>
      targetWeightBps >= 0 &&
      targetWeightBps <= 10000 &&
      driftBandBps >= 0 &&
      driftBandBps <= 10000 &&
      actualAmount >= Decimal.zero;
}

enum CapitalAllocationAction {
  transferIn,
  transferOut,
  withinBand,
  policyBlocked,
  noCounterparty,
}

class CapitalAllocationDecision {
  const CapitalAllocationDecision({
    required this.nodeId,
    required this.nodeName,
    required this.actualWeight,
    required this.targetWeight,
    required this.actualAmount,
    required this.targetAmount,
    required this.action,
    required this.explanation,
  });

  final String nodeId;
  final String nodeName;
  final double actualWeight;
  final double targetWeight;
  final Money actualAmount;
  final Money targetAmount;
  final CapitalAllocationAction action;
  final String explanation;

  double get deviation => actualWeight - targetWeight;
}

class CapitalAllocationTransfer {
  const CapitalAllocationTransfer({
    required this.fromNodeId,
    required this.toNodeId,
    required this.amount,
    required this.explanation,
  });

  final String fromNodeId;
  final String toNodeId;
  final Money amount;
  final String explanation;
}

class CapitalAllocationPlan {
  const CapitalAllocationPlan({
    required this.totalAssets,
    required this.decisions,
    required this.transfers,
  });

  final Money totalAssets;
  final Map<String, CapitalAllocationDecision> decisions;
  final List<CapitalAllocationTransfer> transfers;

  bool get hasBlockedDecisions => decisions.values.any(
    (decision) =>
        decision.action == CapitalAllocationAction.policyBlocked ||
        decision.action == CapitalAllocationAction.noCounterparty,
  );

  bool get requiresAction => decisions.values.any(
    (decision) => decision.action != CapitalAllocationAction.withinBand,
  );
}

/// Policy-aware allocator shared by universe → portfolio and
/// portfolio → strategy-group levels.
class CapitalAllocationEngine {
  const CapitalAllocationEngine();

  CapitalAllocationPlan compute({
    required List<CapitalAllocationNode> nodes,
    required String baseCurrency,
  }) {
    if (nodes.isEmpty ||
        nodes.any((node) => !node.isValid) ||
        nodes.fold<int>(0, (sum, node) => sum + node.targetWeightBps) !=
            10000) {
      throw const FormatException(
        'Capital allocation nodes must be valid and sum to 10000 basis points.',
      );
    }
    final total = nodes.fold<Decimal>(
      Decimal.zero,
      (sum, node) => sum + node.actualAmount,
    );
    final states = [
      for (final node in nodes)
        _NodeState(
          node: node,
          total: total,
          target:
              (total *
                      Decimal.fromInt(node.targetWeightBps) /
                      Decimal.fromInt(10000))
                  .toDecimal(scaleOnInfinitePrecision: 8),
        ),
    ];
    final transfers = _matchTransfers(states, baseCurrency);
    final totalAssets = Money(total, baseCurrency);
    return CapitalAllocationPlan(
      totalAssets: totalAssets,
      transfers: List.unmodifiable(transfers),
      decisions: Map.unmodifiable({
        for (final state in states)
          state.node.id: _decision(state, transfers, totalAssets),
      }),
    );
  }

  List<CapitalAllocationTransfer> _matchTransfers(
    List<_NodeState> states,
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
    final transfers = <CapitalAllocationTransfer>[];
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
          CapitalAllocationTransfer(
            fromNodeId: source.state.node.id,
            toNodeId: destination.state.node.id,
            amount: Money(amount, currency),
            explanation:
                '${source.state.node.name} exceeds its target outside the '
                'drift band; ${destination.state.node.name} is below target.',
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

  CapitalAllocationDecision _decision(
    _NodeState state,
    List<CapitalAllocationTransfer> transfers,
    Money totalAssets,
  ) {
    final outgoing = transfers.any(
      (transfer) => transfer.fromNodeId == state.node.id,
    );
    final incoming = transfers.any(
      (transfer) => transfer.toNodeId == state.node.id,
    );
    final action = switch ((outgoing, incoming)) {
      (true, _) => CapitalAllocationAction.transferOut,
      (_, true) => CapitalAllocationAction.transferIn,
      _ when state.withinBand => CapitalAllocationAction.withinBand,
      _ when state.policyBlocksRequiredTransfer =>
        CapitalAllocationAction.policyBlocked,
      _ => CapitalAllocationAction.noCounterparty,
    };
    final explanation = switch (action) {
      CapitalAllocationAction.transferOut =>
        'Above target; policy allows capital to leave this allocation.',
      CapitalAllocationAction.transferIn =>
        'Below target; policy allows capital to enter this allocation.',
      CapitalAllocationAction.withinBand =>
        'Allocation weight is inside its configured drift band.',
      CapitalAllocationAction.policyBlocked =>
        'The transfer policy intentionally blocks the required movement.',
      CapitalAllocationAction.noCounterparty =>
        'Outside the drift band, but no eligible counterparty can fund it.',
    };
    final total = totalAssets.amount.toDouble();
    return CapitalAllocationDecision(
      nodeId: state.node.id,
      nodeName: state.node.name,
      actualWeight: total <= 0 ? 0 : state.node.actualAmount.toDouble() / total,
      targetWeight: state.node.targetWeightBps / 10000,
      actualAmount: Money(state.node.actualAmount, totalAssets.currency),
      targetAmount: Money(state.target, totalAssets.currency),
      action: action,
      explanation: explanation,
    );
  }
}

class _NodeState {
  const _NodeState({
    required this.node,
    required this.total,
    required this.target,
  });

  final CapitalAllocationNode node;
  final Decimal total;
  final Decimal target;

  Decimal get deviation => node.actualAmount - target;

  Decimal get bandAmount =>
      (total * Decimal.fromInt(node.driftBandBps) / Decimal.fromInt(10000))
          .toDecimal(scaleOnInfinitePrecision: 8);

  bool get withinBand => deviation.abs() <= bandAmount;

  Decimal get transferableSurplus {
    if (withinBand ||
        deviation <= Decimal.zero ||
        node.transferPolicy != GroupTransferPolicy.bidirectional) {
      return Decimal.zero;
    }
    return deviation;
  }

  Decimal get acceptableDeficit {
    if (withinBand ||
        deviation >= Decimal.zero ||
        node.transferPolicy == GroupTransferPolicy.isolated) {
      return Decimal.zero;
    }
    return -deviation;
  }

  bool get policyBlocksRequiredTransfer {
    if (withinBand) return false;
    if (deviation > Decimal.zero) {
      return node.transferPolicy != GroupTransferPolicy.bidirectional;
    }
    return node.transferPolicy == GroupTransferPolicy.isolated;
  }
}

class _MutableAmount {
  _MutableAmount(this.state, this.remaining);

  final _NodeState state;
  Decimal remaining;
}
