import 'dart:math' as math;

import 'package:decimal/decimal.dart';

import 'fire_goal.dart';
import 'fire_projection.dart';

/// Pure calculator that turns a [FireGoal] + current net worth + a set of
/// annual-return assumptions into a [FireDashboardView].
///
/// Stateless — call from any thread. The math is straight FV-of-an-annuity
/// with monthly compounding plus an inflation-adjusted target line:
///
/// ```
///   m  = (1 + r)^(1/12) - 1     // monthly return
///   π  = (1 + i)^(1/12) - 1     // monthly inflation
///   NW(t) = NW₀ * (1 + m)^t + S * ((1 + m)^t - 1) / m       // m ≠ 0
///   NW(t) = NW₀ + S * t                                      // m = 0
///   target(t) = T₀ * (1 + π)^t
/// ```
///
/// `t` is in months, contributions land at the end of each month
/// (ordinary annuity). The crossing point is found by linear scan over
/// `t ∈ [0, maxHorizonMonths]`. Linear scan beats binary search here
/// because the gap function `NW(t) − target(t)` can dip back below zero
/// in pathological cases (e.g. negative surplus, real return below
/// inflation) and a monotonic root finder would lock onto the wrong
/// branch. 1200 iterations of cheap arithmetic is well under a millisecond.
class FireCalculator {
  const FireCalculator({
    this.maxHorizonMonths = 1200,
    this.sampleCount = 60,
    this.conservativeRate = 0.03,
    this.neutralRate = 0.06,
    this.aggressiveRate = 0.10,
  });

  /// Hard cap on the search window — 100 years. Anything beyond this is
  /// reported as "unreachable" because the user almost certainly didn't
  /// mean to plan that far out and the inflation-adjusted target has long
  /// since outrun any realistic compounding by then.
  final int maxHorizonMonths;

  /// Target number of points to emit per scenario for charting. The actual
  /// count may be slightly smaller (rounding) or +1 (we always pin the
  /// crossing month).
  final int sampleCount;

  /// Annualized return assumption for the conservative scenario.
  final double conservativeRate;

  /// Annualized return assumption for the neutral scenario.
  final double neutralRate;

  /// Annualized return assumption for the aggressive scenario.
  final double aggressiveRate;

  /// Build the full dashboard view in one pass.
  ///
  /// [liveAnnualReturn] is the user's actual XIRR-derived rate (FIR-55).
  /// When non-null it adds a fourth `live` scenario *and* anchors the
  /// sensitivity readout to the live rate; when null the sensitivity uses
  /// [neutralRate] so the user still gets a meaningful "what if I save 20%
  /// more" answer before XIRR is wired into the dashboard.
  FireDashboardView buildView({
    required FireGoal goal,
    required Decimal currentNetWorth,
    required String baseCurrency,
    required DateTime start,
    double? liveAnnualReturn,
  }) {
    final tiers = <(FireScenarioTier, double)>[
      (FireScenarioTier.conservative, conservativeRate),
      (FireScenarioTier.neutral, neutralRate),
      (FireScenarioTier.aggressive, aggressiveRate),
      if (liveAnnualReturn != null)
        (FireScenarioTier.live, liveAnnualReturn),
    ];

    // Pre-compute crossings so every scenario shares one chart horizon —
    // mismatched horizons produce visually misleading curves where the
    // aggressive line "ends early" past the FIRE point.
    final crossings = <FireScenarioTier, int?>{};
    for (final (tier, rate) in tiers) {
      crossings[tier] = _findMonthsToTarget(
        annualReturn: rate,
        goal: goal,
        currentNetWorth: currentNetWorth,
      );
    }

    final commonHorizon = _pickHorizon(crossings.values);
    final scenarios = <FireScenario>[];
    for (final (tier, rate) in tiers) {
      scenarios.add(_projectScenario(
        tier: tier,
        annualReturn: rate,
        goal: goal,
        currentNetWorth: currentNetWorth,
        start: start,
        horizonMonths: commonHorizon,
        crossingMonth: crossings[tier],
      ));
    }

    final baseRate = liveAnnualReturn ?? neutralRate;
    final lowSurplus = _scaleDecimal(goal.monthlySurplus, 0.8);
    final highSurplus = _scaleDecimal(goal.monthlySurplus, 1.2);

    final baselineKey = liveAnnualReturn != null
        ? FireScenarioTier.live
        : FireScenarioTier.neutral;

    return FireDashboardView(
      goal: goal,
      start: start,
      baseCurrency: baseCurrency,
      currentNetWorth: currentNetWorth,
      scenarios: scenarios,
      sensitivity: FireSensitivity(
        baselineMonths: crossings[baselineKey],
        lowSurplusMonths: _findMonthsToTarget(
          annualReturn: baseRate,
          goal: goal.copyWith(monthlySurplus: lowSurplus),
          currentNetWorth: currentNetWorth,
        ),
        highSurplusMonths: _findMonthsToTarget(
          annualReturn: baseRate,
          goal: goal.copyWith(monthlySurplus: highSurplus),
          currentNetWorth: currentNetWorth,
        ),
        lowSurplus: lowSurplus,
        highSurplus: highSurplus,
      ),
    );
  }

  /// Months until [currentNetWorth] (compounded under [annualReturn] with
  /// [FireGoal.monthlySurplus] contributions) catches up with the inflation-
  /// adjusted target. `null` when not reached within
  /// [maxHorizonMonths].
  ///
  /// Exposed so callers (and tests) can ask the question without paying for
  /// the full chart projection.
  int? _findMonthsToTarget({
    required double annualReturn,
    required FireGoal goal,
    required Decimal currentNetWorth,
  }) {
    final nw0 = currentNetWorth.toDouble();
    final target0 = goal.targetAmount.toDouble();
    if (target0 <= 0) return null;
    if (nw0 >= target0) return 0;

    final m = _monthlyRate(annualReturn);
    final pi = _monthlyRate(goal.inflationRate);
    final s = goal.monthlySurplus.toDouble();

    for (var t = 1; t <= maxHorizonMonths; t++) {
      final nw = _networthAt(nw0: nw0, s: s, m: m, t: t);
      final target = _targetAt(target0: target0, pi: pi, t: t);
      if (nw.isNaN || nw.isInfinite) return null;
      if (nw >= target) return t;
    }
    return null;
  }

  FireScenario _projectScenario({
    required FireScenarioTier tier,
    required double annualReturn,
    required FireGoal goal,
    required Decimal currentNetWorth,
    required DateTime start,
    required int horizonMonths,
    required int? crossingMonth,
  }) {
    final nw0 = currentNetWorth.toDouble();
    final target0 = goal.targetAmount.toDouble();
    final m = _monthlyRate(annualReturn);
    final pi = _monthlyRate(goal.inflationRate);
    final s = goal.monthlySurplus.toDouble();

    final step = math.max(1, (horizonMonths / sampleCount).ceil());
    final pinned = <int>{0, horizonMonths};
    if (crossingMonth != null) pinned.add(crossingMonth);
    final monthIndices = <int>{
      for (var t = 0; t <= horizonMonths; t += step) t,
      ...pinned,
    }.toList()
      ..sort();

    final points = <FireProjectionPoint>[
      for (final t in monthIndices)
        FireProjectionPoint(
          date: _addMonths(start, t),
          netWorth: _networthAt(nw0: nw0, s: s, m: m, t: t),
          target: _targetAt(target0: target0, pi: pi, t: t),
        ),
    ];

    final reachedTargetAtFire = crossingMonth == null
        ? null
        : _targetAt(target0: target0, pi: pi, t: crossingMonth);

    return FireScenario(
      tier: tier,
      annualReturn: annualReturn,
      monthsToTarget: crossingMonth,
      points: points,
      targetAmountAtFire: reachedTargetAtFire,
    );
  }

  /// Pick a chart horizon that comfortably contains every scenario's
  /// crossing — long enough that the aggressive curve doesn't end the
  /// instant it touches target, short enough that the conservative curve
  /// doesn't drown the chart in flat blue line.
  ///
  /// - all reached → `1.2 × max(crossings)` clamped to `[60, max]`
  /// - none reached → 30 years (a typical "long term" planning window)
  int _pickHorizon(Iterable<int?> crossings) {
    final reached = crossings.whereType<int>().toList();
    if (reached.isEmpty) {
      return math.min(maxHorizonMonths, 360);
    }
    final maxReached = reached.reduce(math.max);
    final padded = (maxReached * 1.2).round() + 12;
    return math.min(maxHorizonMonths, math.max(60, padded));
  }

  static double _monthlyRate(double annualRate) {
    if (annualRate == 0) return 0;
    return math.pow(1 + annualRate, 1 / 12).toDouble() - 1;
  }

  static double _networthAt({
    required double nw0,
    required double s,
    required double m,
    required int t,
  }) {
    if (m == 0) return nw0 + s * t;
    final factor = math.pow(1 + m, t).toDouble();
    return nw0 * factor + s * (factor - 1) / m;
  }

  static double _targetAt({
    required double target0,
    required double pi,
    required int t,
  }) {
    if (pi == 0) return target0;
    return target0 * math.pow(1 + pi, t).toDouble();
  }

  /// Add `months` calendar months to [d]. The day-of-month is preserved when
  /// possible — `Jan 31 + 1 month` collapses to `Feb 28/29` because the
  /// `DateTime` constructor normalises overflow. Preserves the UTC flag so
  /// callers that pin a deterministic start in tests get bit-equal results.
  static DateTime _addMonths(DateTime d, int months) {
    return d.isUtc
        ? DateTime.utc(d.year, d.month + months, d.day)
        : DateTime(d.year, d.month + months, d.day);
  }

  /// Decimal × double via a 4-decimal-digit intermediate. The factors we
  /// multiply by (`0.8`, `1.2`, `0.04`) are exact at 4 digits, so the
  /// rounding here is bit-for-bit reproducible.
  static Decimal _scaleDecimal(Decimal value, double factor) {
    final f = Decimal.parse(factor.toStringAsFixed(4));
    return value * f;
  }
}
