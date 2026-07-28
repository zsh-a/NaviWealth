import 'package:naviwealth/core/sync/sync_meta.dart';

import 'portfolio_rebalance_group.dart';

/// Explicit denominator for portfolio-level allocation.
class RebalanceUniverse {
  const RebalanceUniverse({
    required this.id,
    required this.name,
    required this.baseCurrency,
    required this.createdAt,
    required this.archived,
    required this.sync,
  });

  final String id;
  final String name;
  final String baseCurrency;
  final DateTime createdAt;
  final bool archived;
  final SyncMeta sync;
}

/// A portfolio's capital policy inside one [RebalanceUniverse].
class PortfolioAllocationTarget {
  const PortfolioAllocationTarget({
    required this.id,
    required this.universeId,
    required this.portfolioId,
    required this.targetWeightBps,
    required this.driftBandBps,
    required this.transferPolicy,
    required this.sync,
  });

  final String id;
  final String universeId;
  final String portfolioId;
  final int targetWeightBps;
  final int driftBandBps;
  final GroupTransferPolicy transferPolicy;
  final SyncMeta sync;

  bool get isValid =>
      targetWeightBps >= 0 &&
      targetWeightBps <= 10000 &&
      driftBandBps >= 0 &&
      driftBandBps <= 10000;

  PortfolioAllocationTarget copyWith({
    int? targetWeightBps,
    int? driftBandBps,
    GroupTransferPolicy? transferPolicy,
    SyncMeta? sync,
  }) {
    return PortfolioAllocationTarget(
      id: id,
      universeId: universeId,
      portfolioId: portfolioId,
      targetWeightBps: targetWeightBps ?? this.targetWeightBps,
      driftBandBps: driftBandBps ?? this.driftBandBps,
      transferPolicy: transferPolicy ?? this.transferPolicy,
      sync: sync ?? this.sync,
    );
  }
}

class UniverseAllocationTarget {
  const UniverseAllocationTarget({
    required this.universe,
    required this.portfolios,
  });

  final RebalanceUniverse universe;
  final List<PortfolioAllocationTarget> portfolios;

  bool get isValid =>
      portfolios.isNotEmpty &&
      portfolios.every((target) => target.isValid) &&
      portfolios.fold<int>(0, (sum, target) => sum + target.targetWeightBps) ==
          10000;
}
