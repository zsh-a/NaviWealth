import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart';

import 'fire_goal.dart';

/// One scenario tier in the multi-scenario projection.
///
/// The three default tiers (`conservative` / `neutral` / `aggressive`) sit
/// next to an optional `live` tier seeded from the user's actual XIRR. The
/// labels are persisted as enum keys (not as colors / annual rates) so a UI
/// theme change or a tweak to the default rates won't invalidate any
/// downstream telemetry.
enum FireScenarioTier {
  conservative,
  neutral,
  aggressive,

  /// Annualized return computed from the user's actual cash flows (FIR-55).
  /// Only present in the result when a live rate is supplied.
  live,
}

/// One sample on the projection curve for a scenario.
@immutable
class FireProjectionPoint {
  const FireProjectionPoint({
    required this.date,
    required this.netWorth,
    required this.target,
  });

  /// Timestamp the projection is sampled at. Always >= the projection's
  /// `start`.
  final DateTime date;

  /// Projected net worth at [date], in the goal's base currency.
  final double netWorth;

  /// Inflation-adjusted target at [date]. Plotting both lets the UI show
  /// when the projection crosses the target.
  final double target;
}

/// Outcome for a single scenario.
@immutable
class FireScenario {
  const FireScenario({
    required this.tier,
    required this.annualReturn,
    required this.monthsToTarget,
    required this.points,
    required this.targetAmountAtFire,
  });

  final FireScenarioTier tier;

  /// Annualized return as a decimal (`0.06` = 6%).
  final double annualReturn;

  /// Months from `start` until projected net worth meets the inflation-
  /// adjusted target. `null` when the target is not reached within the
  /// projection horizon — typically because `monthlySurplus = 0` and the
  /// real return is non-positive.
  final int? monthsToTarget;

  /// Inflation-adjusted target value at the moment of FIRE. Useful for the
  /// "you'll need ¥X in nominal terms" hint. `null` when [monthsToTarget]
  /// is null.
  final double? targetAmountAtFire;

  /// Projection points (one per sample step). The list always contains at
  /// least the starting point. When the target is reached within the
  /// horizon, the last point sits at-or-just-after the crossing month so
  /// the chart line clearly meets the target line.
  final List<FireProjectionPoint> points;

  /// Convenience: years (with decimal) until FIRE. `null` when not reached.
  double? get yearsToTarget {
    final m = monthsToTarget;
    return m == null ? null : m / 12.0;
  }

  bool get isReached => monthsToTarget == 0;
  bool get isUnreachable => monthsToTarget == null;
}

/// Sensitivity readout: how the months-to-FIRE shifts when the user's
/// monthly surplus moves ±20%.
@immutable
class FireSensitivity {
  const FireSensitivity({
    required this.baselineMonths,
    required this.lowSurplusMonths,
    required this.highSurplusMonths,
    required this.lowSurplus,
    required this.highSurplus,
  });

  /// Baseline (current surplus) months-to-FIRE. Mirrors the matching
  /// scenario's [FireScenario.monthsToTarget] so the UI doesn't have to
  /// re-look-up the scenario.
  final int? baselineMonths;

  /// Months-to-FIRE if the user saves 20% less per month.
  final int? lowSurplusMonths;

  /// Months-to-FIRE if the user saves 20% more per month.
  final int? highSurplusMonths;

  /// Surplus value used for the low-end leg.
  final Decimal lowSurplus;

  /// Surplus value used for the high-end leg.
  final Decimal highSurplus;

  /// Months saved by raising the surplus 20%. Positive = sooner.
  /// `null` when either leg is unreachable.
  int? get monthsSavedAtHighSurplus {
    final base = baselineMonths;
    final hi = highSurplusMonths;
    if (base == null || hi == null) return null;
    return base - hi;
  }

  /// Months added by lowering the surplus 20%. Positive = later.
  int? get monthsAddedAtLowSurplus {
    final base = baselineMonths;
    final lo = lowSurplusMonths;
    if (base == null || lo == null) return null;
    return lo - base;
  }
}

/// Top-level data the FIRE dashboard renders against.
@immutable
class FireDashboardView {
  const FireDashboardView({
    required this.goal,
    required this.start,
    required this.baseCurrency,
    required this.currentNetWorth,
    required this.scenarios,
    required this.sensitivity,
  });

  final FireGoal goal;

  /// Anchor date the projection runs from — typically `DateTime.now()` at
  /// build time. Captured so the chart's X axis is deterministic and
  /// reproducible in tests.
  final DateTime start;

  final String baseCurrency;

  final Decimal currentNetWorth;

  final List<FireScenario> scenarios;

  final FireSensitivity sensitivity;

  /// `currentNetWorth / targetAmount`, clamped to `[0, 1]`. `null` when the
  /// goal target is zero — i.e. the user has not configured one yet.
  double? get progressRatio {
    if (goal.targetAmount <= Decimal.zero) return null;
    final ratio = (currentNetWorth / goal.targetAmount).toDouble();
    if (ratio.isNaN || ratio.isInfinite) return null;
    return ratio.clamp(0.0, 1.0);
  }

  /// Safe monthly withdrawal under the 4% rule, in today's purchasing
  /// power. Returns a `double` because the rule itself (`/ 12`) introduces
  /// a non-terminating decimal — the UI rounds to currency precision when
  /// formatting, so we don't add a faux-precise Decimal hop here.
  double get safeMonthlyWithdrawalAmount {
    return goal.targetAmount.toDouble() * 0.04 / 12;
  }

  /// Surplus over `monthlyExpenses` of the safe monthly withdrawal. Positive
  /// → the target supports the planned lifestyle; negative → user is
  /// under-saving for their stated expenses.
  double get safeWithdrawalSurplus {
    return safeMonthlyWithdrawalAmount - goal.monthlyExpenses.toDouble();
  }
}
