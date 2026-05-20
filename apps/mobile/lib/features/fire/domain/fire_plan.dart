import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart';

import '../../../domain/values/money.dart';
import 'fire_goal.dart';

/// How free the user wants to live once work is optional. The mode is a
/// planning posture, not a derived metric — it nudges the safe-withdrawal
/// default and the tone of the suggested actions (a `coast` planner cares
/// about ETA; a `fat` planner cares about resilience headroom).
enum FireLifestyleMode {
  /// Minimal expenses, aggressive savings — Lean FIRE.
  lean,

  /// The default — current lifestyle, normal SWR.
  standard,

  /// Generous expenses, larger buffer — Fat FIRE.
  fat,

  /// Stop adding principal; let compounding carry you to the target.
  coast,

  /// Partial work income covers part of the spend — Barista FIRE.
  barista,
}

/// A purpose-tagged pile of money the user mentally earmarks (a medical
/// buffer, family-support fund, a dream purchase). Stress tests draw these
/// down before declaring the plan broken.
enum FireReserveKind { medical, family, dream, emergency, other }

@immutable
class FireReserve {
  const FireReserve({
    required this.id,
    required this.label,
    required this.amount,
    required this.kind,
  });

  final String id;
  final String label;
  final Money amount;
  final FireReserveKind kind;

  FireReserve copyWith({String? label, Money? amount, FireReserveKind? kind}) {
    return FireReserve(
      id: id,
      label: label ?? this.label,
      amount: amount ?? this.amount,
      kind: kind ?? this.kind,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'label': label,
    'amount': amount.amount.toString(),
    'currency': amount.currency,
    'kind': kind.name,
  };

  factory FireReserve.fromJson(Map<String, Object?> json, String baseCurrency) {
    final currency = (json['currency'] as String?) ?? baseCurrency;
    final amount = Decimal.tryParse('${json['amount']}') ?? Decimal.zero;
    return FireReserve(
      id: (json['id'] as String?) ?? '',
      label: (json['label'] as String?) ?? '',
      amount: Money(amount, currency),
      kind: FireReserveKind.values.firstWhere(
        (k) => k.name == json['kind'],
        orElse: () => FireReserveKind.other,
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is FireReserve &&
      other.id == id &&
      other.label == label &&
      other.amount == amount &&
      other.kind == kind;

  @override
  int get hashCode => Object.hash(id, label, amount, kind);
}

/// Tunable parameters the stress-test engine (Phase 3) reads. They have
/// sensible defaults so the user only sees them under "advanced".
@immutable
class FireRiskSettings {
  const FireRiskSettings({
    this.marketDrawdownPct = 0.35,
    this.expenseShockPct = 0.20,
    this.fxShockPct = 0.10,
    this.oneOffShockAmount = 0,
  });

  /// Headline bear-market drawdown applied to the growth bucket.
  final double marketDrawdownPct;

  /// Sustained living-cost increase used by the "expense +X%" test.
  final double expenseShockPct;

  /// Currency swing magnitude used by the FX-shock test.
  final double fxShockPct;

  /// One-off medical / family-support outlay used by the lump-sum test, in
  /// the plan's base currency. Stress tests work in ranges, not pennies —
  /// double is precise enough and lets the field carry a const default.
  final double oneOffShockAmount;

  FireRiskSettings copyWith({
    double? marketDrawdownPct,
    double? expenseShockPct,
    double? fxShockPct,
    double? oneOffShockAmount,
  }) {
    return FireRiskSettings(
      marketDrawdownPct: marketDrawdownPct ?? this.marketDrawdownPct,
      expenseShockPct: expenseShockPct ?? this.expenseShockPct,
      fxShockPct: fxShockPct ?? this.fxShockPct,
      oneOffShockAmount: oneOffShockAmount ?? this.oneOffShockAmount,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'market_drawdown_pct': marketDrawdownPct,
    'expense_shock_pct': expenseShockPct,
    'fx_shock_pct': fxShockPct,
    'one_off_shock_amount': oneOffShockAmount,
  };

  factory FireRiskSettings.fromJson(Map<String, Object?> json) {
    double d(Object? v, double fallback) =>
        v is num ? v.toDouble() : fallback;
    return FireRiskSettings(
      marketDrawdownPct: d(json['market_drawdown_pct'], 0.35),
      expenseShockPct: d(json['expense_shock_pct'], 0.20),
      fxShockPct: d(json['fx_shock_pct'], 0.10),
      oneOffShockAmount: d(json['one_off_shock_amount'], 0),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is FireRiskSettings &&
      other.marketDrawdownPct == marketDrawdownPct &&
      other.expenseShockPct == expenseShockPct &&
      other.fxShockPct == fxShockPct &&
      other.oneOffShockAmount == oneOffShockAmount;

  @override
  int get hashCode => Object.hash(
    marketDrawdownPct,
    expenseShockPct,
    fxShockPct,
    oneOffShockAmount,
  );
}

/// The full FIRE OS planning input. A superset of the legacy [FireGoal] —
/// the projection engine still consumes a [FireGoal] (via [toGoal]) so the
/// existing math and golden tests stay bit-compatible; the extra fields
/// drive the state engine, buckets, stress tests and reviews.
///
/// Per `docs/roadmap-fire-os.md` §7.1 the MVP keeps this in local
/// preferences (no sync-protocol change); Phase 6 migrates it to a synced
/// Drift table.
@immutable
class FirePlan {
  const FirePlan({
    required this.id,
    required this.baseCurrency,
    required this.monthlyExpenses,
    required this.monthlySurplus,
    required this.inflationRate,
    required this.targetNetWorth,
    required this.safeWithdrawalRate,
    required this.targetCashBucketMonths,
    required this.lifestyleMode,
    required this.reserves,
    required this.riskSettings,
  });

  /// The unconfigured seed. `targetNetWorth == 0` is the sentinel the UI
  /// keys the onboarding card off, matching [FireGoal.unset].
  factory FirePlan.unset({String baseCurrency = 'CNY'}) {
    return FirePlan(
      id: kDefaultFirePlanId,
      baseCurrency: baseCurrency,
      monthlyExpenses: Decimal.zero,
      monthlySurplus: Decimal.zero,
      inflationRate: FireGoal.defaultInflationRate,
      targetNetWorth: Decimal.zero,
      safeWithdrawalRate: defaultSafeWithdrawalRate,
      targetCashBucketMonths: defaultCashBucketMonths,
      lifestyleMode: FireLifestyleMode.standard,
      reserves: const <FireReserve>[],
      riskSettings: const FireRiskSettings(),
    );
  }

  /// Compose a plan from the legacy [FireGoal] (the shared, already-persisted
  /// fields) plus the FIRE-OS-only extras. This keeps a single source of
  /// truth — [FireGoal] stays the storage for the shared fields.
  factory FirePlan.fromGoal(
    FireGoal goal, {
    required String baseCurrency,
    double safeWithdrawalRate = defaultSafeWithdrawalRate,
    int targetCashBucketMonths = defaultCashBucketMonths,
    FireLifestyleMode lifestyleMode = FireLifestyleMode.standard,
    List<FireReserve> reserves = const <FireReserve>[],
    FireRiskSettings riskSettings = const FireRiskSettings(),
  }) {
    return FirePlan(
      id: kDefaultFirePlanId,
      baseCurrency: baseCurrency,
      monthlyExpenses: goal.monthlyExpenses,
      monthlySurplus: goal.monthlySurplus,
      inflationRate: goal.inflationRate,
      targetNetWorth: goal.targetAmount,
      safeWithdrawalRate: safeWithdrawalRate,
      targetCashBucketMonths: targetCashBucketMonths,
      lifestyleMode: lifestyleMode,
      reserves: reserves,
      riskSettings: riskSettings,
    );
  }

  static const String kDefaultFirePlanId = 'default';

  /// Trinity-study 4% rule — the conventional safe withdrawal rate.
  static const double defaultSafeWithdrawalRate = 0.04;

  /// One year of expenses as the default cash-bucket target.
  static const int defaultCashBucketMonths = 12;

  final String id;
  final String baseCurrency;

  /// Projected monthly expenses at FIRE (base currency). Shared with
  /// [FireGoal.monthlyExpenses].
  final Decimal monthlyExpenses;

  /// Current monthly savings — drives the projection contribution. Shared
  /// with [FireGoal.monthlySurplus].
  final Decimal monthlySurplus;

  /// Annual inflation as a decimal (`0.03` = 3%).
  final double inflationRate;

  /// FIRE target net worth in today's purchasing power. Shared with
  /// [FireGoal.targetAmount].
  final Decimal targetNetWorth;

  /// Safe withdrawal rate as a decimal (`0.04` = 4%).
  final double safeWithdrawalRate;

  /// How many months of expenses the cash bucket should hold.
  final int targetCashBucketMonths;

  final FireLifestyleMode lifestyleMode;
  final List<FireReserve> reserves;
  final FireRiskSettings riskSettings;

  bool get isConfigured => targetNetWorth > Decimal.zero;

  /// Annual expense in base currency (`monthlyExpenses × 12`).
  Money get annualExpense =>
      Money(monthlyExpenses * Decimal.fromInt(12), baseCurrency);

  Money get monthlyExpenseMoney => Money(monthlyExpenses, baseCurrency);

  Money get targetNetWorthMoney => Money(targetNetWorth, baseCurrency);

  /// Total earmarked reserves in base currency. Reserves in other
  /// currencies are ignored here (the caller surfaces FX gaps separately).
  Money get totalReserves {
    var sum = Money.zero(baseCurrency);
    for (final r in reserves) {
      if (r.amount.currency == baseCurrency) sum += r.amount;
    }
    return sum;
  }

  /// Project this plan through the legacy [FireCalculator]. Bit-compatible
  /// with the pre-FIRE-OS behaviour: the calculator never saw the extra
  /// fields, so deriving a [FireGoal] reproduces the old result exactly.
  FireGoal toGoal() => FireGoal(
    targetAmount: targetNetWorth,
    monthlyExpenses: monthlyExpenses,
    monthlySurplus: monthlySurplus,
    inflationRate: inflationRate,
  );

  FirePlan copyWith({
    String? baseCurrency,
    Decimal? monthlyExpenses,
    Decimal? monthlySurplus,
    double? inflationRate,
    Decimal? targetNetWorth,
    double? safeWithdrawalRate,
    int? targetCashBucketMonths,
    FireLifestyleMode? lifestyleMode,
    List<FireReserve>? reserves,
    FireRiskSettings? riskSettings,
  }) {
    return FirePlan(
      id: id,
      baseCurrency: baseCurrency ?? this.baseCurrency,
      monthlyExpenses: monthlyExpenses ?? this.monthlyExpenses,
      monthlySurplus: monthlySurplus ?? this.monthlySurplus,
      inflationRate: inflationRate ?? this.inflationRate,
      targetNetWorth: targetNetWorth ?? this.targetNetWorth,
      safeWithdrawalRate: safeWithdrawalRate ?? this.safeWithdrawalRate,
      targetCashBucketMonths:
          targetCashBucketMonths ?? this.targetCashBucketMonths,
      lifestyleMode: lifestyleMode ?? this.lifestyleMode,
      reserves: reserves ?? this.reserves,
      riskSettings: riskSettings ?? this.riskSettings,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is FirePlan &&
      other.id == id &&
      other.baseCurrency == baseCurrency &&
      other.monthlyExpenses == monthlyExpenses &&
      other.monthlySurplus == monthlySurplus &&
      other.inflationRate == inflationRate &&
      other.targetNetWorth == targetNetWorth &&
      other.safeWithdrawalRate == safeWithdrawalRate &&
      other.targetCashBucketMonths == targetCashBucketMonths &&
      other.lifestyleMode == lifestyleMode &&
      listEquals(other.reserves, reserves) &&
      other.riskSettings == riskSettings;

  @override
  int get hashCode => Object.hash(
    id,
    baseCurrency,
    monthlyExpenses,
    monthlySurplus,
    inflationRate,
    targetNetWorth,
    safeWithdrawalRate,
    targetCashBucketMonths,
    lifestyleMode,
    Object.hashAll(reserves),
    riskSettings,
  );
}
