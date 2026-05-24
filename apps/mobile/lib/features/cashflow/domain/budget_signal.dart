/// Classified budget posture for a single month — the bridge between
/// the budget read-model and FIRE / dashboard / AI consumers
/// (`docs/roadmap-next.md` §3.2).
///
/// Pure derivation over [MonthlyBudgetSummary]: no IO, no state. FIRE
/// engine consumes this through a provider so its safety-level
/// computation can fold "user is sustained over budget" into the
/// existing thresholds without a tight FireState ↔ BudgetRepository
/// dependency.
library;

import 'budget_summary.dart';

/// Discrete classification of how the month is tracking against budget.
enum BudgetSignal {
  /// User has not set any budgets, or every set budget has zero spend
  /// (typically the first day of the month). Treated as a quiet state —
  /// FIRE doesn't dock safety level for it.
  noData,

  /// On or under target across the whole month. Spend ≤ 80% of budget.
  comfortable,

  /// Approaching the cap. Spend in `(80%, 100%]` of total budget, OR
  /// at least one category over budget but total still under cap.
  strained,

  /// Total monthly spend exceeds total monthly budget. The strongest
  /// signal — FIRE should bump cash-bucket pressure when this fires
  /// over consecutive months.
  overBudget,
}

extension BudgetSignalWire on BudgetSignal {
  String get wire => switch (this) {
        BudgetSignal.noData => 'no_data',
        BudgetSignal.comfortable => 'comfortable',
        BudgetSignal.strained => 'strained',
        BudgetSignal.overBudget => 'over_budget',
      };
}

/// Bands used by [budgetSignalFor]. Kept as a top-level constant so the
/// dashboard can show the user where the next band kicks in.
const double kBudgetStrainedLowerBound = 0.80;

/// Derive a [BudgetSignal] from a rolled-up [summary].
///
/// Pure function. The bands are chosen to align with the existing
/// `fireOsLowCashBucket` insight thresholds — when "spend > budget" the
/// FIRE engine can fairly assume cash runway is at risk and surface
/// the corresponding insight even if cash-bucket-months hasn't yet
/// crossed its own threshold.
BudgetSignal budgetSignalFor(MonthlyBudgetSummary summary) {
  if (summary.categories.isEmpty) return BudgetSignal.noData;
  final budgeted = summary.totalBudgeted.amount.toDouble();
  if (budgeted <= 0) return BudgetSignal.noData;
  final spent = summary.totalSpent.amount.toDouble();
  if (spent <= 0 && !summary.categories.any((c) => c.isOverBudget)) {
    return BudgetSignal.noData;
  }
  if (summary.isOverBudget) return BudgetSignal.overBudget;
  final ratio = spent / budgeted;
  if (ratio < kBudgetStrainedLowerBound) {
    // Even when total is comfortable, a single over-budget category is
    // signal worth surfacing — the user is leaning hard on one bucket
    // and the others may not absorb a true overrun mid-month.
    if (summary.categories.any((c) => c.isOverBudget)) {
      return BudgetSignal.strained;
    }
    return BudgetSignal.comfortable;
  }
  return BudgetSignal.strained;
}
