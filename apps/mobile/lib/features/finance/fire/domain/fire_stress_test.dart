import 'package:flutter/foundation.dart';

import 'package:naviwealth/domain/values/money.dart';
import 'fire_action.dart';

/// Snake-case wire name for a [FireStressScenario]. AI tools and review
/// history pin on these strings; keep them stable.
String _scenarioWire(FireStressScenario s) {
  switch (s) {
    case FireStressScenario.marketDrawdown:
      return 'market_drawdown';
    case FireStressScenario.expenseSurge:
      return 'expense_surge';
    case FireStressScenario.oneOffShock:
      return 'one_off_shock';
    case FireStressScenario.fxShock:
      return 'fx_shock';
    case FireStressScenario.cashDepletion:
      return 'cash_depletion';
  }
}

/// Identifies a stress scenario. The codes are persisted in AI tool output
/// and review history, so don't rename them after they ship.
enum FireStressScenario {
  /// Equity sleeve drawdown — magnitude lives in `params.drawdownPct`.
  marketDrawdown,

  /// Sustained living-cost increase — magnitude in `params.expenseShockPct`.
  expenseSurge,

  /// One-off medical / family-support outlay — magnitude in `params.amount`.
  oneOffShock,

  /// FX rate move against the user — magnitude in `params.fxShockPct`.
  fxShock,

  /// Cash bucket runs dry over a horizon — `params.months` is the horizon.
  cashDepletion,
}

/// Verdict the engine returns for each scenario. Mirrors [FireSafetyLevel]
/// at the per-test granularity so the UI can colour each row.
enum FireStressVerdict { safe, cautious, danger }

/// Inputs to a single stress run. Defaults come from the plan's
/// [FireRiskSettings] but the engine accepts overrides so the AI can
/// simulate "what if the drawdown is 50% instead of 35%".
@immutable
class FireStressParams {
  const FireStressParams({
    this.drawdownPct,
    this.expenseShockPct,
    this.fxShockPct,
    this.amount,
    this.months,
  });

  final double? drawdownPct;
  final double? expenseShockPct;
  final double? fxShockPct;
  final double? amount;
  final int? months;
}

/// Result for one scenario. Numbers in base currency. The numeric fields
/// stay raw (no rounding) so AI tools can quote them precisely; the UI
/// applies its own formatting.
@immutable
class FireStressResult {
  const FireStressResult({
    required this.scenario,
    required this.verdict,
    required this.params,
    required this.netWorthAfter,
    required this.investableAssetsAfter,
    required this.annualSpendAfter,
    required this.withdrawalRateAfter,
    required this.cashBucketMonthsAfter,
    required this.recommendedActions,
    this.note,
  });

  final FireStressScenario scenario;
  final FireStressVerdict verdict;
  final FireStressParams params;

  final Money netWorthAfter;
  final Money investableAssetsAfter;
  final Money annualSpendAfter;
  final double withdrawalRateAfter;
  final double cashBucketMonthsAfter;

  /// Suggested follow-up actions if the scenario tripped the verdict.
  final List<FireAction> recommendedActions;

  final String? note;

  Map<String, Object?> toJson() {
    double? cleanDouble(double v) => v.isFinite ? v : null;
    return <String, Object?>{
      'scenario': _scenarioWire(scenario),
      'verdict': verdict.name,
      'params': <String, Object?>{
        if (params.drawdownPct != null) 'drawdown_pct': params.drawdownPct,
        if (params.expenseShockPct != null)
          'expense_shock_pct': params.expenseShockPct,
        if (params.fxShockPct != null) 'fx_shock_pct': params.fxShockPct,
        if (params.amount != null) 'amount': params.amount,
        if (params.months != null) 'months': params.months,
      },
      'net_worth_after': netWorthAfter.amount.toString(),
      'investable_after': investableAssetsAfter.amount.toString(),
      'annual_spend_after': annualSpendAfter.amount.toString(),
      'withdrawal_rate_after': cleanDouble(withdrawalRateAfter),
      'cash_bucket_months_after': cleanDouble(cashBucketMonthsAfter),
      'currency': netWorthAfter.currency,
      'recommended_actions': recommendedActions
          .map((a) => a.toJson())
          .toList(growable: false),
      if (note != null) 'note': note,
    };
  }

  @override
  bool operator ==(Object other) =>
      other is FireStressResult &&
      other.scenario == scenario &&
      other.verdict == verdict &&
      other.netWorthAfter == netWorthAfter &&
      other.investableAssetsAfter == investableAssetsAfter &&
      other.annualSpendAfter == annualSpendAfter &&
      other.withdrawalRateAfter == withdrawalRateAfter &&
      other.cashBucketMonthsAfter == cashBucketMonthsAfter &&
      listEquals(other.recommendedActions, recommendedActions) &&
      other.note == note;

  @override
  int get hashCode => Object.hash(
    scenario,
    verdict,
    netWorthAfter,
    investableAssetsAfter,
    annualSpendAfter,
    withdrawalRateAfter,
    cashBucketMonthsAfter,
    Object.hashAll(recommendedActions),
    note,
  );
}
