import 'hierarchical_rebalance_engine.dart';
import 'universe_rebalance_engine.dart';

enum RebalanceStage {
  portfolioCapital,
  portfolioBlocked,
  groupCapital,
  groupBlocked,
  assetTrades,
  complete,
}

class RebalanceStageState {
  const RebalanceStageState(this.stage);

  final RebalanceStage stage;

  bool get isPortfolioStage =>
      stage == RebalanceStage.portfolioCapital ||
      stage == RebalanceStage.portfolioBlocked;

  bool get isGroupStage =>
      stage == RebalanceStage.groupCapital ||
      stage == RebalanceStage.groupBlocked;

  bool get blocksAssetTrades => isPortfolioStage || isGroupStage;

  bool get isBlocked =>
      stage == RebalanceStage.portfolioBlocked ||
      stage == RebalanceStage.groupBlocked;
}

abstract final class RebalanceStageResolver {
  static RebalanceStageState resolve({
    UniverseRebalancePlan? universePlan,
    PortfolioRebalancePlan? portfolioPlan,
  }) {
    final universeCapital = universePlan?.capitalPlan;
    if (universeCapital?.requiresAction ?? false) {
      return RebalanceStageState(
        universeCapital!.transfers.isNotEmpty
            ? RebalanceStage.portfolioCapital
            : RebalanceStage.portfolioBlocked,
      );
    }

    if (portfolioPlan?.hasUnresolvedCapital ?? false) {
      return RebalanceStageState(
        portfolioPlan!.transfers.isNotEmpty
            ? RebalanceStage.groupCapital
            : RebalanceStage.groupBlocked,
      );
    }

    final hasAssetTrades =
        portfolioPlan?.groups.any(
          (group) => !(group.internalPlan?.isBalanced ?? true),
        ) ??
        false;
    return RebalanceStageState(
      hasAssetTrades ? RebalanceStage.assetTrades : RebalanceStage.complete,
    );
  }
}
