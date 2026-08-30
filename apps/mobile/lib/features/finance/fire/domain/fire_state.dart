import 'package:flutter/foundation.dart';

import 'package:naviwealth/features/finance/domain/fx/money.dart';

import 'fire_action.dart';
import 'fire_plan.dart';
import 'fire_stress_test.dart';

/// The top-level traffic-light. Mirrors `docs/roadmap-fire-os.md` §1:
/// > 安全 / 谨慎 / 危险.
///
/// `unconfigured` is a fourth state the UI keys onboarding off — it never
/// flows into a stress-test verdict.
enum FireSafetyLevel { unconfigured, safe, cautious, danger }

/// The full FIRE OS read model. `FireState` is *computed* from the local
/// ledger, holdings, cashflow and [FirePlan] (see
/// `fire_state_service.dart`) — it is never persisted directly.
@immutable
class FireState {
  const FireState({
    required this.plan,
    required this.baseCurrency,
    required this.netWorth,
    required this.investableAssets,
    required this.liquidAssets,
    required this.annualSpend,
    required this.monthlyExpense,
    required this.withdrawalRate,
    required this.cashBucketMonths,
    required this.fireEtaMonths,
    required this.safetyLevel,
    required this.suggestedActions,
    required this.stressTests,
    required this.currencyMismatchCount,
    required this.computedAt,
    this.annualSpendSource = FireAnnualSpendSource.plan,
  });

  /// The plan inputs this state was computed against. Carrying it on
  /// the state keeps consumers from having to re-look-up the plan in
  /// downstream calculations.
  final FirePlan plan;

  final String baseCurrency;

  /// Total assets minus total liabilities in base currency.
  final Money netWorth;

  /// Sum of liquid + market-traded assets — what the plan can actually
  /// withdraw from. Excludes real estate and vehicles.
  final Money investableAssets;

  /// Cash + demand deposits. Cash runway divides this by monthly expense.
  final Money liquidAssets;

  /// Annualised expense in base currency. Drawn from trailing 12-month
  /// cashflow when available, otherwise from `plan.annualExpense`.
  /// See [annualSpendSource] for which.
  final Money annualSpend;

  /// `annualSpend / 12` as money — used for cash-runway math.
  final Money monthlyExpense;

  /// `annualSpend / investableAssets`. `0` when there is no spend at
  /// all; `double.infinity` when there is spend but no investable
  /// assets — the UI gates on `.isFinite`.
  final double withdrawalRate;

  /// `liquidAssets / monthlyExpense`. `0` when there is no monthly
  /// expense; `double.infinity` when there is liquidity but no recorded
  /// expense (effectively unlimited runway).
  final double cashBucketMonths;

  /// Baseline ETA to FIRE in months — from the projection engine's
  /// `live` or `neutral` scenario. `null` when not reached within the
  /// projection horizon or the plan is unconfigured.
  final int? fireEtaMonths;

  final FireSafetyLevel safetyLevel;

  /// Deterministic, data-derived recommendations. AI never invents
  /// these — it explains them and may [propose] changes to the plan.
  final List<FireAction> suggestedActions;

  /// Stress-test verdicts. Often empty on the state itself; live stress
  /// lives on [fireStressTestsProvider].
  final List<FireStressResult> stressTests;

  /// Number of holdings whose FX rate could not be resolved into
  /// [baseCurrency]. Non-zero pushes the state to `cautious` so the
  /// user notices that the totals omit something.
  final int currencyMismatchCount;

  /// Anchor timestamp — set by the caller (usually `DateTime.now()`).
  final DateTime computedAt;

  /// Which source [annualSpend] was sourced from.
  final FireAnnualSpendSource annualSpendSource;

  bool get isConfigured => plan.isConfigured;

  /// Convenience: a withdrawal rate that downstream consumers can safely
  /// format. `null` when [withdrawalRate] is infinite.
  double? get finiteWithdrawalRate =>
      withdrawalRate.isFinite ? withdrawalRate : null;

  /// Months of runway rounded for display. `null` when infinite.
  int? get cashBucketMonthsRounded {
    if (!cashBucketMonths.isFinite) return null;
    return cashBucketMonths.round();
  }

  /// JSON shape consumed by `get_fire_state`.
  Map<String, Object?> toJson() {
    double? finite(double v) => v.isFinite ? v : null;
    return <String, Object?>{
      'computed_at': computedAt.toUtc().toIso8601String(),
      'base_currency': baseCurrency,
      'plan_id': plan.id,
      'is_configured': isConfigured,
      'safety_level': safetyLevel.name,
      'net_worth': netWorth.amount.toString(),
      'investable_assets': investableAssets.amount.toString(),
      'liquid_assets': liquidAssets.amount.toString(),
      'annual_spend': annualSpend.amount.toString(),
      'annual_spend_source': annualSpendSource.name,
      'monthly_expense': monthlyExpense.amount.toString(),
      'withdrawal_rate': finite(withdrawalRate),
      'safe_withdrawal_rate': plan.safeWithdrawalRate,
      'cash_bucket_months': finite(cashBucketMonths),
      'target_cash_bucket_months': plan.targetCashBucketMonths,
      'fire_eta_months': fireEtaMonths,
      'currency_mismatch_count': currencyMismatchCount,
      'lifestyle_mode': plan.lifestyleMode.name,
      'suggested_actions': suggestedActions
          .map((a) => a.toJson())
          .toList(growable: false),
      'stress_tests': stressTests
          .map((s) => s.toJson())
          .toList(growable: false),
    };
  }
}

/// Which source supplied [FireState.annualSpend].
enum FireAnnualSpendSource {
  /// Trailing 12-month cashflow expense, annualised.
  trailing12m,

  /// `plan.annualExpense` — stated planning input.
  plan,
}
