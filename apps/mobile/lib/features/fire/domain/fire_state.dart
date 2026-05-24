import 'package:flutter/foundation.dart';

import '../../../domain/values/money.dart';
import 'fire_action.dart';
import 'fire_bucket.dart';
import 'fire_bucket_allocator.dart';
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
/// `fire_state_service.dart`) — it is never persisted directly. That
/// keeps the sync protocol untouched in MVP per roadmap §7.1.
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
    required this.buckets,
    required this.stressTests,
    required this.currencyMismatchCount,
    required this.computedAt,
    this.annualSpendSource = FireAnnualSpendSource.plan,
    this.unmappedHoldings = const <FireUnmappedHolding>[],
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

  /// Cash + demand deposits. The cash-bucket coverage divides this by
  /// the monthly expense.
  final Money liquidAssets;

  /// Annualised expense in base currency. Drawn from trailing 12-month
  /// cashflow when available, otherwise from `plan.annualExpense`.
  /// See [annualSpendSource] for which.
  final Money annualSpend;

  /// `annualSpend / 12` as money — used for the cash-bucket math.
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

  /// Phase-2-and-up: per-bucket coverage. Empty list in Phase 1.
  final List<FireBucketState> buckets;

  /// Phase-3-and-up: stress-test verdicts. Empty list in Phase 1.
  final List<FireStressResult> stressTests;

  /// Number of holdings whose FX rate could not be resolved into
  /// [baseCurrency]. Non-zero pushes the state to `cautious` so the
  /// user notices that the totals omit something.
  final int currencyMismatchCount;

  /// Anchor timestamp — set by the caller (usually `DateTime.now()`).
  /// Stored on the state for the AI tool output and the diagnostics
  /// header.
  final DateTime computedAt;

  /// Which source [annualSpend] was sourced from. The AI tool surfaces
  /// this so the user knows whether the engine inferred from history or
  /// fell back on their stated plan.
  final FireAnnualSpendSource annualSpendSource;

  /// Assets the allocator couldn't slot into any bucket (real estate,
  /// vehicles, etc.). The user can override with an explicit
  /// [FireBucketRule]; until then they sit on the side of the buckets
  /// view, surfaced to keep the picture honest.
  final List<FireUnmappedHolding> unmappedHoldings;

  bool get isConfigured => plan.isConfigured;

  /// Convenience: a withdrawal rate that downstream consumers can safely
  /// format. `null` when [withdrawalRate] is infinite (spend > 0 but no
  /// investable assets) so callers don't accidentally render `inf%`.
  double? get finiteWithdrawalRate =>
      withdrawalRate.isFinite ? withdrawalRate : null;

  /// Convenience: months of runway clamped to a representable integer
  /// for the gauge. `null` when there is no monthly expense at all (the
  /// "infinite" case the UI displays as "—").
  int? get cashBucketMonthsRounded {
    if (!cashBucketMonths.isFinite) return null;
    return cashBucketMonths.round();
  }

  /// JSON shape consumed by `get_fire_state` (Phase 5). Stable; do not
  /// reshape silently — AI prompts pin on these key names.
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
      'buckets': buckets
          .map(
            (b) => <String, Object?>{
              'role': b.role.name,
              'current_value': b.currentValue.amount.toString(),
              'target_value': b.targetValue.amount.toString(),
              'coverage_ratio': b.coverageRatio,
              'status': b.status.name,
              'asset_ids': b.assetIds,
            },
          )
          .toList(growable: false),
      'stress_tests': stressTests
          .map((s) => s.toJson())
          .toList(growable: false),
      'unmapped_holdings': unmappedHoldings
          .map(
            (u) => <String, Object?>{
              'id': u.id,
              'name': u.name,
              'value': u.value.amount.toString(),
              'currency': u.value.currency,
              'reason': u.reason,
            },
          )
          .toList(growable: false),
    };
  }
}

/// Which source supplied [FireState.annualSpend]. Surfaced so the user (and
/// the AI) know whether the engine is reading actuals or planning input.
enum FireAnnualSpendSource {
  /// Trailing 12-month cashflow expense, annualised. Preferred when
  /// there is at least one month of ledger data.
  trailing12m,

  /// `plan.annualExpense` — the user's stated planning input. Used
  /// during onboarding before any ledger history exists.
  plan,
}
