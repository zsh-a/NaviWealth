import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart';

/// User-supplied inputs that drive the FIRE dashboard.
///
/// All amounts are denominated in the dashboard's base currency;
/// converting per-asset values into base happens upstream in the dashboard
/// snapshot. The goal itself is currency-agnostic — UI labels the figures
/// using the active base currency.
@immutable
class FireGoal {
  const FireGoal({
    required this.targetAmount,
    required this.monthlyExpenses,
    required this.monthlySurplus,
    required this.inflationRate,
  });

  /// Default seed used when the user has not configured a goal yet.
  /// `targetAmount = 0` is the sentinel "unconfigured" state — the dashboard
  /// renders the setup card instead of a progress gauge until it is set.
  factory FireGoal.unset() {
    return FireGoal(
      targetAmount: Decimal.zero,
      monthlyExpenses: Decimal.zero,
      monthlySurplus: Decimal.zero,
      inflationRate: defaultInflationRate,
    );
  }

  /// 3% — typical long-run consumer inflation pin used as the seed for the
  /// inflation slider. Users in higher-inflation regimes should override.
  static const double defaultInflationRate = 0.03;

  /// FIRE target in today's purchasing power (base currency).
  final Decimal targetAmount;

  /// Projected monthly expenses at FIRE — used by the 4% rule check.
  final Decimal monthlyExpenses;

  /// Current monthly savings (income − expenses). Drives the projection's
  /// recurring contribution.
  final Decimal monthlySurplus;

  /// Annual inflation as a decimal (`0.03` = 3%). The nominal target grows
  /// at this rate so the 4% rule retains real purchasing power.
  final double inflationRate;

  bool get isConfigured => targetAmount > Decimal.zero;

  FireGoal copyWith({
    Decimal? targetAmount,
    Decimal? monthlyExpenses,
    Decimal? monthlySurplus,
    double? inflationRate,
  }) {
    return FireGoal(
      targetAmount: targetAmount ?? this.targetAmount,
      monthlyExpenses: monthlyExpenses ?? this.monthlyExpenses,
      monthlySurplus: monthlySurplus ?? this.monthlySurplus,
      inflationRate: inflationRate ?? this.inflationRate,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is FireGoal &&
      other.targetAmount == targetAmount &&
      other.monthlyExpenses == monthlyExpenses &&
      other.monthlySurplus == monthlySurplus &&
      other.inflationRate == inflationRate;

  @override
  int get hashCode =>
      Object.hash(targetAmount, monthlyExpenses, monthlySurplus, inflationRate);

  @override
  String toString() =>
      'FireGoal(target=$targetAmount, monthlyExpenses=$monthlyExpenses, '
      'monthlySurplus=$monthlySurplus, inflation=$inflationRate)';
}
