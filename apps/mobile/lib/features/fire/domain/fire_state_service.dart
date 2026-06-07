import 'package:decimal/decimal.dart';

import '../../../core/format/formatters.dart';
import '../../../domain/values/money.dart';
import 'fire_action.dart';
import 'fire_bucket.dart';
import 'fire_bucket_allocator.dart';
import 'fire_plan.dart';
import 'fire_state.dart';
import 'fire_stress_test.dart';

/// Pure function: turn a [FirePlan] + actuals into a [FireState]. No I/O,
/// no providers, no LLM — every output is derivable from the inputs.
/// That keeps the state engine unit-testable, reproducible inside an
/// isolate, and shape-compatible with the `get_fire_state` AI tool.
///
/// Buckets and stress tests are passed in (rather than computed here) so
/// Phase 2 and Phase 3 can layer on top without restructuring this
/// function.
FireState computeFireState({
  required FirePlan plan,
  required Money netWorth,
  required Money investableAssets,
  required Money liquidAssets,
  required Money? trailingAnnualSpend,
  required int? fireEtaMonths,
  required int currencyMismatchCount,
  required DateTime computedAt,
  List<FireBucketState> buckets = const <FireBucketState>[],
  List<FireStressResult> stressTests = const <FireStressResult>[],
  List<FireUnmappedHolding> unmappedHoldings = const <FireUnmappedHolding>[],
}) {
  final base = plan.baseCurrency;
  _requireBase(base, netWorth, 'netWorth');
  _requireBase(base, investableAssets, 'investableAssets');
  _requireBase(base, liquidAssets, 'liquidAssets');
  if (trailingAnnualSpend != null) {
    _requireBase(base, trailingAnnualSpend, 'trailingAnnualSpend');
  }

  // Annual spend source: prefer trailing actuals when present, else the
  // planner's stated annual expense. Onboarding falls all the way through
  // to zero, which is fine — the UI shows the unconfigured state.
  final usingTrailing = trailingAnnualSpend != null;
  final annualSpend = usingTrailing
      ? trailingAnnualSpend
      : plan.isConfigured
      ? plan.annualExpense
      : Money.zero(base);

  final monthlyExpense = Money(
    (annualSpend.amount / Decimal.fromInt(12)).toDecimal(
      scaleOnInfinitePrecision: 2,
    ),
    base,
  );

  final withdrawalRate = _computeWithdrawalRate(
    annualSpend: annualSpend,
    investableAssets: investableAssets,
  );
  final cashBucketMonths = _computeCashBucketMonths(
    liquidAssets: liquidAssets,
    monthlyExpense: monthlyExpense,
  );

  final safetyLevel = _safetyLevel(
    plan: plan,
    netWorth: netWorth,
    withdrawalRate: withdrawalRate,
    cashBucketMonths: cashBucketMonths,
    currencyMismatchCount: currencyMismatchCount,
  );

  final actions = _suggestedActions(
    plan: plan,
    netWorth: netWorth,
    monthlyExpense: monthlyExpense,
    liquidAssets: liquidAssets,
    withdrawalRate: withdrawalRate,
    cashBucketMonths: cashBucketMonths,
    currencyMismatchCount: currencyMismatchCount,
    safetyLevel: safetyLevel,
  );

  return FireState(
    plan: plan,
    baseCurrency: base,
    netWorth: netWorth,
    investableAssets: investableAssets,
    liquidAssets: liquidAssets,
    annualSpend: annualSpend,
    monthlyExpense: monthlyExpense,
    withdrawalRate: withdrawalRate,
    cashBucketMonths: cashBucketMonths,
    fireEtaMonths: plan.isConfigured ? fireEtaMonths : null,
    safetyLevel: safetyLevel,
    suggestedActions: actions,
    buckets: buckets,
    stressTests: stressTests,
    currencyMismatchCount: currencyMismatchCount,
    computedAt: computedAt,
    annualSpendSource: usingTrailing
        ? FireAnnualSpendSource.trailing12m
        : FireAnnualSpendSource.plan,
    unmappedHoldings: unmappedHoldings,
  );
}

/// `annualSpend / investableAssets`. Returns `0` when there is no spend at
/// all, `double.infinity` when there is spend but no investable assets —
/// the latter is a load-bearing signal that the plan is breaking down.
double _computeWithdrawalRate({
  required Money annualSpend,
  required Money investableAssets,
}) {
  final spend = annualSpend.amount.toDouble();
  final inv = investableAssets.amount.toDouble();
  if (inv <= 0) return spend <= 0 ? 0.0 : double.infinity;
  return spend / inv;
}

/// `liquidAssets / monthlyExpense`. Symmetric infinity / zero handling to
/// [_computeWithdrawalRate].
double _computeCashBucketMonths({
  required Money liquidAssets,
  required Money monthlyExpense,
}) {
  final liq = liquidAssets.amount.toDouble();
  final mex = monthlyExpense.amount.toDouble();
  if (mex <= 0) return liq <= 0 ? 0.0 : double.infinity;
  return liq / mex;
}

FireSafetyLevel _safetyLevel({
  required FirePlan plan,
  required Money netWorth,
  required double withdrawalRate,
  required double cashBucketMonths,
  required int currencyMismatchCount,
}) {
  if (!plan.isConfigured) return FireSafetyLevel.unconfigured;

  final swr = plan.safeWithdrawalRate;
  final targetMonths = plan.targetCashBucketMonths.toDouble();

  // Danger gates — any one trips the headline.
  final netWorthBroken = netWorth.amount <= Decimal.zero;
  final wrHopeless = withdrawalRate.isFinite
      ? withdrawalRate > swr * 1.5
      : true; // infinity → spend > 0 with no assets — danger.
  final cashCritical = cashBucketMonths < targetMonths * 0.5;
  if (netWorthBroken || wrHopeless || cashCritical) {
    return FireSafetyLevel.danger;
  }

  // Caution gates — softer signals.
  final wrCautious = withdrawalRate.isFinite && withdrawalRate > swr;
  final cashLow = cashBucketMonths < targetMonths;
  final fxGap = currencyMismatchCount > 0;
  if (wrCautious || cashLow || fxGap) {
    return FireSafetyLevel.cautious;
  }

  return FireSafetyLevel.safe;
}

List<FireAction> _suggestedActions({
  required FirePlan plan,
  required Money netWorth,
  required Money monthlyExpense,
  required Money liquidAssets,
  required double withdrawalRate,
  required double cashBucketMonths,
  required int currencyMismatchCount,
  required FireSafetyLevel safetyLevel,
}) {
  final base = plan.baseCurrency;
  final actions = <FireAction>[];

  if (!plan.isConfigured) {
    actions.add(
      const FireAction(
        kind: FireActionKind.configurePlan,
        severity: FireActionSeverity.critical,
      ),
    );
    return actions;
  }

  // Cash-bucket shortfall — always surface when below target, even if the
  // headline is `safe`, so the user has a calm prompt before it bites.
  final cashTarget = monthlyExpense.scale(
    Decimal.fromInt(plan.targetCashBucketMonths),
  );
  final cashShortfallAmount = cashTarget.amount - liquidAssets.amount;
  if (cashShortfallAmount > Decimal.zero &&
      monthlyExpense.amount > Decimal.zero) {
    final critical = cashBucketMonths < plan.targetCashBucketMonths * 0.5;
    actions.add(
      FireAction(
        kind: FireActionKind.topUpCashBucket,
        severity: critical
            ? FireActionSeverity.critical
            : FireActionSeverity.warning,
        amount: Money(cashShortfallAmount, base),
        months: plan.targetCashBucketMonths,
      ),
    );
  }

  // Withdrawal-rate signal.
  if (!withdrawalRate.isFinite ||
      withdrawalRate > plan.safeWithdrawalRate * 1.5) {
    actions.add(
      FireAction(
        kind: FireActionKind.reduceSpending,
        severity: FireActionSeverity.critical,
        pct: withdrawalRate.isFinite
            ? withdrawalRate - plan.safeWithdrawalRate
            : null,
      ),
    );
  } else if (withdrawalRate > plan.safeWithdrawalRate) {
    actions
      ..add(
        FireAction(
          kind: FireActionKind.reduceSpending,
          severity: FireActionSeverity.warning,
          pct: withdrawalRate - plan.safeWithdrawalRate,
        ),
      )
      ..add(
        const FireAction(
          kind: FireActionKind.delayDiscretionary,
          severity: FireActionSeverity.warning,
        ),
      );
  }

  // Net-worth break — debt larger than assets.
  if (netWorth.amount <= Decimal.zero) {
    actions.add(
      const FireAction(
        kind: FireActionKind.buildRiskReserve,
        severity: FireActionSeverity.critical,
      ),
    );
  }

  // FX gaps — make them visible so the user knows the totals are partial.
  if (currencyMismatchCount > 0) {
    actions.add(
      FireAction(
        kind: FireActionKind.fixCurrencyGap,
        severity: FireActionSeverity.warning,
        months: currencyMismatchCount,
      ),
    );
  }

  if (actions.isEmpty) {
    actions.add(
      const FireAction(
        kind: FireActionKind.holdSteady,
        severity: FireActionSeverity.info,
      ),
    );
  }

  return List.unmodifiable(actions);
}

void _requireBase(String base, Money money, String label) {
  if (money.currency != base) {
    throw ArgumentError(
      '$label must be in base currency $base; got ${money.currency}',
    );
  }
}

/// Compute a what-if [FireState] off an existing baseline.
///
/// Re-runs [computeFireState] with the plan fields the caller overrode,
/// preserving everything else (net worth, investable, liquid, mismatch
/// count, etc.). When the baseline's spend was sourced from trailing
/// actuals, the overrides scale the trailing total via
/// [trailingScale] (default 1.0); otherwise the plan-driven
/// `annualExpense` carries the change automatically.
///
/// Pure: no providers, no IO. The simulations card and the
/// `simulate_fire_plan` AI tool both call through this helper so
/// "what the user sees" and "what the LLM saw" are byte-identical.
FireState simulateFireState({
  required FireState baseline,
  Decimal? monthlyExpenses,
  Decimal? monthlySurplus,
  double? inflationRate,
  double? safeWithdrawalRate,
  int? targetCashBucketMonths,
  double trailingScale = 1.0,
}) {
  final plan = baseline.plan.copyWith(
    monthlyExpenses: monthlyExpenses ?? baseline.plan.monthlyExpenses,
    monthlySurplus: monthlySurplus ?? baseline.plan.monthlySurplus,
    inflationRate: inflationRate ?? baseline.plan.inflationRate,
    safeWithdrawalRate: safeWithdrawalRate ?? baseline.plan.safeWithdrawalRate,
    targetCashBucketMonths:
        targetCashBucketMonths ?? baseline.plan.targetCashBucketMonths,
  );
  final useTrailing =
      baseline.annualSpendSource == FireAnnualSpendSource.trailing12m;
  Money? trailing;
  if (useTrailing) {
    final factor = DecimalX.fromDouble(trailingScale, scale: 4);
    trailing = Money(
      baseline.annualSpend.amount * factor,
      baseline.baseCurrency,
    );
  }
  return computeFireState(
    plan: plan,
    netWorth: baseline.netWorth,
    investableAssets: baseline.investableAssets,
    liquidAssets: baseline.liquidAssets,
    trailingAnnualSpend: trailing,
    fireEtaMonths: baseline.fireEtaMonths,
    currencyMismatchCount: baseline.currencyMismatchCount,
    computedAt: baseline.computedAt,
  );
}
