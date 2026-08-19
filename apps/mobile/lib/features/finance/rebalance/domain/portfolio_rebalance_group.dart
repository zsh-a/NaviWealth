import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/finance/investment/domain/strategy/portfolio_strategy.dart';

import 'rebalance_models.dart';

enum GroupTransferPolicy { bidirectional, inflowsOnly, isolated }

GroupTransferPolicy groupTransferPolicyFromWire(String wire) {
  return GroupTransferPolicy.values.firstWhere(
    (value) => value.name == wire,
    orElse: () =>
        throw FormatException('Unknown group transfer policy: $wire.'),
  );
}

/// A capital-owning partition inside one logical portfolio.
///
/// [targetWeightBps] is relative to the portfolio; [internalTarget] is
/// normalized inside this group. Strategy overlays reference a group but do
/// not create another capital owner.
class PortfolioRebalanceGroup {
  const PortfolioRebalanceGroup({
    required this.id,
    required this.portfolioId,
    required this.name,
    required this.strategyKind,
    required this.targetWeightBps,
    required this.driftBandBps,
    required this.transferPolicy,
    required this.internalTarget,
    required this.createdAt,
    required this.archived,
    required this.sync,
  });

  final String id;
  final String portfolioId;
  final String name;
  final PortfolioStrategyKind strategyKind;
  final int targetWeightBps;
  final int driftBandBps;
  final GroupTransferPolicy transferPolicy;
  final TargetAllocation internalTarget;
  final DateTime createdAt;
  final bool archived;
  final SyncMeta sync;

  bool get hasValidWeight =>
      targetWeightBps >= 0 &&
      targetWeightBps <= 10000 &&
      driftBandBps >= 0 &&
      driftBandBps <= 10000;

  PortfolioRebalanceGroup copyWith({
    String? name,
    int? targetWeightBps,
    int? driftBandBps,
    GroupTransferPolicy? transferPolicy,
    TargetAllocation? internalTarget,
    bool? archived,
    SyncMeta? sync,
  }) {
    return PortfolioRebalanceGroup(
      id: id,
      portfolioId: portfolioId,
      name: name ?? this.name,
      strategyKind: strategyKind,
      targetWeightBps: targetWeightBps ?? this.targetWeightBps,
      driftBandBps: driftBandBps ?? this.driftBandBps,
      transferPolicy: transferPolicy ?? this.transferPolicy,
      internalTarget: internalTarget ?? this.internalTarget,
      createdAt: createdAt,
      archived: archived ?? this.archived,
      sync: sync ?? this.sync,
    );
  }
}

class PortfolioRebalanceTarget {
  const PortfolioRebalanceTarget({required this.groups});

  final List<PortfolioRebalanceGroup> groups;

  bool get isValid =>
      groups.isNotEmpty &&
      groups.every(
        (group) => group.hasValidWeight && group.internalTarget.isValid,
      ) &&
      groups.fold<int>(0, (sum, group) => sum + group.targetWeightBps) == 10000;
}
