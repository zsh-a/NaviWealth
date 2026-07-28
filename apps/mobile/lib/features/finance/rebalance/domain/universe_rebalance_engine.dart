import 'package:naviwealth/features/finance/home/domain/dashboard_models.dart';
import 'package:naviwealth/features/finance/investment/domain/models/investment_portfolio.dart';

import 'capital_allocation_engine.dart';
import 'hierarchical_rebalance_engine.dart';
import 'portfolio_rebalance_group.dart';
import 'rebalance_universe.dart';

class PortfolioCapitalPlan {
  const PortfolioCapitalPlan({
    required this.portfolio,
    required this.target,
    required this.capitalDecision,
    required this.strategyPlan,
  });

  final InvestmentPortfolio portfolio;
  final PortfolioAllocationTarget target;
  final CapitalAllocationDecision capitalDecision;
  final PortfolioRebalancePlan strategyPlan;
}

/// Complete capital tree plan: portfolio transfers first, then strategy-group
/// transfers, then each group's internal asset allocation.
class UniverseRebalancePlan {
  const UniverseRebalancePlan({
    required this.universe,
    required this.capitalPlan,
    required this.portfolios,
  });

  final RebalanceUniverse universe;
  final CapitalAllocationPlan capitalPlan;
  final List<PortfolioCapitalPlan> portfolios;

  bool get requiresAction =>
      capitalPlan.requiresAction ||
      portfolios.any((portfolio) => portfolio.strategyPlan.requiresAction);
}

class UniverseRebalanceEngine {
  const UniverseRebalanceEngine({
    required this.portfolioEngine,
    this.capitalEngine = const CapitalAllocationEngine(),
  });

  final HierarchicalRebalanceEngine portfolioEngine;
  final CapitalAllocationEngine capitalEngine;

  UniverseRebalancePlan compute({
    required UniverseAllocationTarget target,
    required Map<String, InvestmentPortfolio> portfoliosById,
    required Map<String, List<PortfolioRebalanceGroup>> groupsByPortfolio,
    required Map<String, Map<String, DashboardSnapshot>>
    snapshotsByPortfolioGroup,
  }) {
    if (!target.isValid) {
      throw const FormatException(
        'Universe portfolio weights must sum to 10000 basis points.',
      );
    }
    final strategyPlans = <String, PortfolioRebalancePlan>{};
    for (final portfolioTarget in target.portfolios) {
      final portfolio = portfoliosById[portfolioTarget.portfolioId];
      final groups = groupsByPortfolio[portfolioTarget.portfolioId];
      if (portfolio == null || groups == null || groups.isEmpty) {
        throw StateError(
          'Portfolio ${portfolioTarget.portfolioId} is incomplete.',
        );
      }
      strategyPlans[portfolio.id] = portfolioEngine.compute(
        target: PortfolioRebalanceTarget(groups: groups),
        snapshotsByGroup: snapshotsByPortfolioGroup[portfolio.id] ?? const {},
        baseCurrency: target.universe.baseCurrency,
      );
    }
    final capitalPlan = capitalEngine.compute(
      baseCurrency: target.universe.baseCurrency,
      nodes: [
        for (final portfolioTarget in target.portfolios)
          CapitalAllocationNode(
            id: portfolioTarget.portfolioId,
            name: portfoliosById[portfolioTarget.portfolioId]!.name,
            targetWeightBps: portfolioTarget.targetWeightBps,
            driftBandBps: portfolioTarget.driftBandBps,
            transferPolicy: portfolioTarget.transferPolicy,
            actualAmount:
                strategyPlans[portfolioTarget.portfolioId]!.totalAssets.amount,
          ),
      ],
    );
    return UniverseRebalancePlan(
      universe: target.universe,
      capitalPlan: capitalPlan,
      portfolios: List.unmodifiable([
        for (final portfolioTarget in target.portfolios)
          PortfolioCapitalPlan(
            portfolio: portfoliosById[portfolioTarget.portfolioId]!,
            target: portfolioTarget,
            capitalDecision:
                capitalPlan.decisions[portfolioTarget.portfolioId]!,
            strategyPlan: strategyPlans[portfolioTarget.portfolioId]!,
          ),
      ]),
    );
  }
}
