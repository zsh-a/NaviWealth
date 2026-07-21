import 'package:decimal/decimal.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';

/// User intent attached to a logical investment portfolio.
///
/// These values seed useful defaults and presentation only. A portfolio stays
/// fully user-defined; the strategy never changes the accounting treatment of
/// its holdings.
enum InvestmentPortfolioStrategy {
  income,
  growth,
  preservation,
  goalLinked,
  custom,
}

InvestmentPortfolioStrategy investmentPortfolioStrategyFromWire(String wire) {
  return InvestmentPortfolioStrategy.values.firstWhere(
    (value) => value.name == wire,
    orElse: () => InvestmentPortfolioStrategy.custom,
  );
}

class InvestmentPortfolio {
  const InvestmentPortfolio({
    required this.id,
    required this.name,
    required this.strategy,
    required this.baseCurrency,
    required this.goalId,
    required this.targetAllocationJson,
    required this.targetAnnualIncome,
    required this.color,
    required this.createdAt,
    required this.archived,
    required this.sync,
  });

  final String id;
  final String name;
  final InvestmentPortfolioStrategy strategy;
  final String? baseCurrency;
  final String? goalId;
  final String? targetAllocationJson;
  final Decimal? targetAnnualIncome;
  final String? color;
  final DateTime createdAt;
  final bool archived;
  final SyncMeta sync;

  InvestmentPortfolio copyWith({
    String? name,
    InvestmentPortfolioStrategy? strategy,
    String? baseCurrency,
    String? goalId,
    String? targetAllocationJson,
    Decimal? targetAnnualIncome,
    String? color,
    bool? archived,
    SyncMeta? sync,
  }) {
    return InvestmentPortfolio(
      id: id,
      name: name ?? this.name,
      strategy: strategy ?? this.strategy,
      baseCurrency: baseCurrency ?? this.baseCurrency,
      goalId: goalId ?? this.goalId,
      targetAllocationJson: targetAllocationJson ?? this.targetAllocationJson,
      targetAnnualIncome: targetAnnualIncome ?? this.targetAnnualIncome,
      color: color ?? this.color,
      createdAt: createdAt,
      archived: archived ?? this.archived,
      sync: sync ?? this.sync,
    );
  }
}

/// Current assignment of a ledger-derived lot to a logical portfolio.
class PortfolioLotMembership {
  const PortfolioLotMembership({
    required this.lotId,
    required this.portfolioId,
    required this.assignedAt,
    required this.sync,
  });

  final String lotId;
  final String portfolioId;
  final DateTime assignedAt;
  final SyncMeta sync;
}
