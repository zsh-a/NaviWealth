import 'package:decimal/decimal.dart';

import 'package:naviwealth/core/format/formatters.dart';
import 'package:naviwealth/features/finance/domain/fx/money.dart';
import 'fire_action.dart';
import 'fire_plan.dart';
import 'fire_state.dart';
import 'fire_stress_test.dart';

/// Run the documented stress-test battery against a [FireState].
///
/// Pure function — no providers, no LLM. Each scenario applies a
/// closed-form shock to the relevant input (investable assets, annual
/// spend, liquid cash, FX exposure) and recomputes the headline
/// metrics. Verdicts compare the post-shock values against the same
/// SWR / cash-bucket thresholds the headline [FireSafetyLevel] uses,
/// so a stress that pushes a `safe` plan to `cautious` reads as a
/// step-up in concern, not a re-labeling exercise.
List<FireStressResult> runStressTests(
  FireState state, {
  FireStressParams? marketDrawdownOverride,
  FireStressParams? expenseSurgeOverride,
  FireStressParams? oneOffShockOverride,
  FireStressParams? fxShockOverride,
  FireStressParams? cashDepletionOverride,
}) {
  if (!state.isConfigured) return const <FireStressResult>[];

  return <FireStressResult>[
    _marketDrawdown(state, marketDrawdownOverride),
    _expenseSurge(state, expenseSurgeOverride),
    _oneOffShock(state, oneOffShockOverride),
    _fxShock(state, fxShockOverride),
    _cashDepletion(state, cashDepletionOverride),
  ];
}

// =====================================================================
//  market drawdown
// =====================================================================

FireStressResult _marketDrawdown(FireState state, FireStressParams? override) {
  final pct =
      (override?.drawdownPct ?? state.plan.riskSettings.marketDrawdownPct)
          .clamp(0.0, 0.99);
  final factor = DecimalX.fromDouble(1 - pct, scale: 4);
  final investableAfter = Money(
    state.investableAssets.amount * factor,
    state.baseCurrency,
  );
  final netWorthAfter = Money(
    state.netWorth.amount -
        (state.investableAssets.amount - investableAfter.amount),
    state.baseCurrency,
  );
  final wrAfter = _withdrawalRate(state.annualSpend, investableAfter);
  final verdict = _verdict(
    state.plan,
    netWorthAfter: netWorthAfter,
    withdrawalRate: wrAfter,
    cashBucketMonths: state.cashBucketMonths,
  );
  return FireStressResult(
    scenario: FireStressScenario.marketDrawdown,
    verdict: verdict,
    params: FireStressParams(drawdownPct: pct),
    netWorthAfter: netWorthAfter,
    investableAssetsAfter: investableAfter,
    annualSpendAfter: state.annualSpend,
    withdrawalRateAfter: wrAfter,
    cashBucketMonthsAfter: state.cashBucketMonths,
    recommendedActions: _actionsFor(verdict),
  );
}

// =====================================================================
//  expense surge
// =====================================================================

FireStressResult _expenseSurge(FireState state, FireStressParams? override) {
  final pct =
      (override?.expenseShockPct ?? state.plan.riskSettings.expenseShockPct)
          .clamp(0.0, 5.0);
  final factor = DecimalX.fromDouble(1 + pct, scale: 4);
  final annualSpendAfter = Money(
    state.annualSpend.amount * factor,
    state.baseCurrency,
  );
  final monthlyAfter = Money(
    (annualSpendAfter.amount / Decimal.fromInt(12)).toDecimal(
      scaleOnInfinitePrecision: 2,
    ),
    state.baseCurrency,
  );
  final wrAfter = _withdrawalRate(annualSpendAfter, state.investableAssets);
  final cashMonthsAfter = _cashBucketMonths(state.liquidAssets, monthlyAfter);
  final verdict = _verdict(
    state.plan,
    netWorthAfter: state.netWorth,
    withdrawalRate: wrAfter,
    cashBucketMonths: cashMonthsAfter,
  );
  return FireStressResult(
    scenario: FireStressScenario.expenseSurge,
    verdict: verdict,
    params: FireStressParams(expenseShockPct: pct),
    netWorthAfter: state.netWorth,
    investableAssetsAfter: state.investableAssets,
    annualSpendAfter: annualSpendAfter,
    withdrawalRateAfter: wrAfter,
    cashBucketMonthsAfter: cashMonthsAfter,
    recommendedActions: _actionsFor(verdict),
  );
}

// =====================================================================
//  one-off shock (medical / family support)
// =====================================================================

FireStressResult _oneOffShock(FireState state, FireStressParams? override) {
  final raw = override?.amount ?? state.plan.riskSettings.oneOffShockAmount;
  final amount = raw < 0 ? 0.0 : raw;
  final shock = DecimalX.fromDouble(amount);
  final liquidAfter = Money(
    state.liquidAssets.amount - shock,
    state.baseCurrency,
  );
  final netWorthAfter = Money(
    state.netWorth.amount - shock,
    state.baseCurrency,
  );
  final investableAfter = Money(
    state.investableAssets.amount - shock,
    state.baseCurrency,
  );
  final cashMonthsAfter = _cashBucketMonths(liquidAfter, state.monthlyExpense);
  final wrAfter = _withdrawalRate(state.annualSpend, investableAfter);
  final verdict = _verdict(
    state.plan,
    netWorthAfter: netWorthAfter,
    withdrawalRate: wrAfter,
    cashBucketMonths: cashMonthsAfter,
  );
  return FireStressResult(
    scenario: FireStressScenario.oneOffShock,
    verdict: verdict,
    params: FireStressParams(amount: amount),
    netWorthAfter: netWorthAfter,
    investableAssetsAfter: investableAfter,
    annualSpendAfter: state.annualSpend,
    withdrawalRateAfter: wrAfter,
    cashBucketMonthsAfter: cashMonthsAfter,
    recommendedActions: _actionsFor(verdict),
  );
}

// =====================================================================
//  FX shock
// =====================================================================

FireStressResult _fxShock(FireState state, FireStressParams? override) {
  // Conservative model: every investable holding carries FX risk. The
  // mismatch count nudges the verdict toward caution even when the
  // numbers say "safe" — surfacing the input gap explicitly.
  final pct = (override?.fxShockPct ?? state.plan.riskSettings.fxShockPct)
      .clamp(0.0, 0.99);
  final factor = DecimalX.fromDouble(1 - pct, scale: 4);
  final investableAfter = Money(
    state.investableAssets.amount * factor,
    state.baseCurrency,
  );
  final netWorthAfter = Money(
    state.netWorth.amount -
        (state.investableAssets.amount - investableAfter.amount),
    state.baseCurrency,
  );
  final wrAfter = _withdrawalRate(state.annualSpend, investableAfter);
  var verdict = _verdict(
    state.plan,
    netWorthAfter: netWorthAfter,
    withdrawalRate: wrAfter,
    cashBucketMonths: state.cashBucketMonths,
  );
  if (state.currencyMismatchCount > 0 && verdict == FireStressVerdict.safe) {
    verdict = FireStressVerdict.cautious;
  }
  return FireStressResult(
    scenario: FireStressScenario.fxShock,
    verdict: verdict,
    params: FireStressParams(fxShockPct: pct),
    netWorthAfter: netWorthAfter,
    investableAssetsAfter: investableAfter,
    annualSpendAfter: state.annualSpend,
    withdrawalRateAfter: wrAfter,
    cashBucketMonthsAfter: state.cashBucketMonths,
    recommendedActions: _actionsFor(verdict),
    note: state.currencyMismatchCount > 0
        ? 'fx_gaps_present_${state.currencyMismatchCount}'
        : null,
  );
}

// =====================================================================
//  cash depletion (no inflow projection)
// =====================================================================

FireStressResult _cashDepletion(FireState state, FireStressParams? override) {
  final horizon = (override?.months ?? state.plan.targetCashBucketMonths).clamp(
    1,
    240,
  );
  final monthly = state.monthlyExpense.amount;
  final liquidAfter = Money(
    monthly > Decimal.zero
        ? state.liquidAssets.amount - monthly * Decimal.fromInt(horizon)
        : state.liquidAssets.amount,
    state.baseCurrency,
  );
  final cashMonthsAfter = _cashBucketMonths(liquidAfter, state.monthlyExpense);
  final verdict = _verdict(
    state.plan,
    netWorthAfter: state.netWorth,
    withdrawalRate: state.withdrawalRate,
    cashBucketMonths: cashMonthsAfter,
  );
  return FireStressResult(
    scenario: FireStressScenario.cashDepletion,
    verdict: verdict,
    params: FireStressParams(months: horizon),
    netWorthAfter: state.netWorth,
    investableAssetsAfter: state.investableAssets,
    annualSpendAfter: state.annualSpend,
    withdrawalRateAfter: state.withdrawalRate,
    cashBucketMonthsAfter: cashMonthsAfter,
    recommendedActions: _actionsFor(verdict),
  );
}

// =====================================================================
//  shared helpers
// =====================================================================

double _withdrawalRate(Money annualSpend, Money investable) {
  final spend = annualSpend.amount.toDouble();
  final inv = investable.amount.toDouble();
  if (inv <= 0) return spend <= 0 ? 0.0 : double.infinity;
  return spend / inv;
}

double _cashBucketMonths(Money liquid, Money monthlyExpense) {
  final liq = liquid.amount.toDouble();
  final mex = monthlyExpense.amount.toDouble();
  if (mex <= 0) return liq <= 0 ? 0.0 : double.infinity;
  return liq / mex;
}

FireStressVerdict _verdict(
  FirePlan plan, {
  required Money netWorthAfter,
  required double withdrawalRate,
  required double cashBucketMonths,
}) {
  final targetMonths = plan.targetCashBucketMonths.toDouble();
  final swr = plan.safeWithdrawalRate;
  final netBroken = netWorthAfter.amount <= Decimal.zero;
  final wrHopeless = !withdrawalRate.isFinite || withdrawalRate > swr * 1.5;
  final cashCritical = cashBucketMonths < targetMonths * 0.5;
  if (netBroken || wrHopeless || cashCritical) {
    return FireStressVerdict.danger;
  }
  final wrCautious = withdrawalRate.isFinite && withdrawalRate > swr;
  final cashLow = cashBucketMonths < targetMonths;
  if (wrCautious || cashLow) return FireStressVerdict.cautious;
  return FireStressVerdict.safe;
}

List<FireAction> _actionsFor(FireStressVerdict verdict) {
  switch (verdict) {
    case FireStressVerdict.safe:
      return const <FireAction>[
        FireAction(
          kind: FireActionKind.holdSteady,
          severity: FireActionSeverity.info,
        ),
      ];
    case FireStressVerdict.cautious:
      return const <FireAction>[
        FireAction(
          kind: FireActionKind.delayDiscretionary,
          severity: FireActionSeverity.warning,
        ),
        FireAction(
          kind: FireActionKind.topUpCashBucket,
          severity: FireActionSeverity.warning,
        ),
      ];
    case FireStressVerdict.danger:
      return const <FireAction>[
        FireAction(
          kind: FireActionKind.reduceSpending,
          severity: FireActionSeverity.critical,
        ),
        FireAction(
          kind: FireActionKind.buildRiskReserve,
          severity: FireActionSeverity.critical,
        ),
      ];
  }
}
