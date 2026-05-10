/// Stable, low-sensitivity portion of [ContextPack].
///
/// Aggregate-only — no merchant names, no account names, no original
/// transactions. The cloud planner caches BaseContext keyed by session;
/// it is only re-uploaded when the device computes a meaningful diff.
library;

enum RiskPreference { conservative, moderate, aggressive }

extension RiskPreferenceWire on RiskPreference {
  String get wire => switch (this) {
    RiskPreference.conservative => 'conservative',
    RiskPreference.moderate => 'moderate',
    RiskPreference.aggressive => 'aggressive',
  };

  static RiskPreference parse(String s) => switch (s) {
    'conservative' => RiskPreference.conservative,
    'moderate' => RiskPreference.moderate,
    'aggressive' => RiskPreference.aggressive,
    _ => RiskPreference.moderate,
  };
}

enum CashflowTrend { improving, stable, worsening, unknown }

extension CashflowTrendWire on CashflowTrend {
  String get wire => switch (this) {
    CashflowTrend.improving => 'improving',
    CashflowTrend.stable => 'stable',
    CashflowTrend.worsening => 'worsening',
    CashflowTrend.unknown => 'unknown',
  };

  static CashflowTrend parse(String s) => switch (s) {
    'improving' => CashflowTrend.improving,
    'stable' => CashflowTrend.stable,
    'worsening' => CashflowTrend.worsening,
    _ => CashflowTrend.unknown,
  };
}

/// Aggregate distribution of accounts. No names, no IDs.
class AccountSummary {
  const AccountSummary({required this.totalCount, required this.byKind});

  final int totalCount;

  /// Bucket count keyed by coarse account kind ('cash', 'deposit',
  /// 'wealth_product', 'security', 'crypto', 'liability', 'other').
  /// Wire strings rather than an enum keep the contract forward
  /// compatible without a schema bump for new kinds.
  final Map<String, int> byKind;

  Map<String, Object?> toJson() => <String, Object?>{
    'total_count': totalCount,
    'by_kind': byKind,
  };

  factory AccountSummary.fromJson(Map<String, Object?> json) {
    final raw = json['by_kind'];
    final byKind = <String, int>{};
    if (raw is Map) {
      for (final entry in raw.entries) {
        final v = entry.value;
        if (v is int) {
          byKind[entry.key.toString()] = v;
        }
      }
    }
    final total = json['total_count'];
    return AccountSummary(
      totalCount: total is int ? total : 0,
      byKind: byKind,
    );
  }
}

/// Rolling cashflow profile, base-currency normalised.
///
/// Decimal amounts ride as strings to preserve exact precision across
/// the Rust / Dart boundary. They are encoded in **minor units** of
/// [baseCurrency] (e.g. cents for USD, fen for CNY) so the wire format
/// is integral.
class CashflowSummary {
  const CashflowSummary({
    required this.baseCurrency,
    required this.monthsCovered,
    required this.averageInflowMinor,
    required this.averageOutflowMinor,
    required this.trend,
  });

  final String baseCurrency;
  final int monthsCovered;
  final String averageInflowMinor;
  final String averageOutflowMinor;
  final CashflowTrend trend;

  Map<String, Object?> toJson() => <String, Object?>{
    'base_currency': baseCurrency,
    'months_covered': monthsCovered,
    'average_inflow_minor': averageInflowMinor,
    'average_outflow_minor': averageOutflowMinor,
    'trend': trend.wire,
  };

  factory CashflowSummary.fromJson(Map<String, Object?> json) {
    final cur = json['base_currency'];
    final months = json['months_covered'];
    final inflow = json['average_inflow_minor'];
    final outflow = json['average_outflow_minor'];
    final trend = json['trend'];
    return CashflowSummary(
      baseCurrency: cur is String ? cur : 'USD',
      monthsCovered: months is int ? months : 0,
      averageInflowMinor: inflow is String ? inflow : '0',
      averageOutflowMinor: outflow is String ? outflow : '0',
      trend: trend is String
          ? CashflowTrendWire.parse(trend)
          : CashflowTrend.unknown,
    );
  }
}

class FireGoalSummary {
  const FireGoalSummary({
    required this.targetMinor,
    required this.currency,
    required this.progressFraction,
    this.yearsRemainingEstimate,
  });

  final String targetMinor;
  final String currency;

  /// 0..1 fraction of progress toward the target. Capped at 1.0 once
  /// the goal is met.
  final double progressFraction;

  /// Best-effort remaining years given current cashflow trend. `null`
  /// means unknown / insufficient data.
  final double? yearsRemainingEstimate;

  Map<String, Object?> toJson() => <String, Object?>{
    'target_minor': targetMinor,
    'currency': currency,
    'progress_fraction': progressFraction,
    if (yearsRemainingEstimate != null)
      'years_remaining_estimate': yearsRemainingEstimate,
  };

  factory FireGoalSummary.fromJson(Map<String, Object?> json) {
    final tgt = json['target_minor'];
    final cur = json['currency'];
    final prog = json['progress_fraction'];
    final years = json['years_remaining_estimate'];
    return FireGoalSummary(
      targetMinor: tgt is String ? tgt : '0',
      currency: cur is String ? cur : 'USD',
      progressFraction: prog is num ? prog.toDouble() : 0,
      yearsRemainingEstimate: years is num ? years.toDouble() : null,
    );
  }
}

class BaseContext {
  const BaseContext({
    required this.preferredCurrency,
    required this.riskPreference,
    required this.accounts,
    required this.cashflow,
    this.fireGoal,
  });

  final String preferredCurrency;
  final RiskPreference riskPreference;
  final AccountSummary accounts;
  final CashflowSummary cashflow;
  final FireGoalSummary? fireGoal;

  Map<String, Object?> toJson() => <String, Object?>{
    'preferred_currency': preferredCurrency,
    'risk_preference': riskPreference.wire,
    'accounts': accounts.toJson(),
    'cashflow': cashflow.toJson(),
    if (fireGoal != null) 'fire_goal': fireGoal!.toJson(),
  };

  factory BaseContext.fromJson(Map<String, Object?> json) {
    final cur = json['preferred_currency'];
    final risk = json['risk_preference'];
    final accountsRaw = json['accounts'];
    final cashflowRaw = json['cashflow'];
    final fireRaw = json['fire_goal'];
    return BaseContext(
      preferredCurrency: cur is String ? cur : 'USD',
      riskPreference: risk is String
          ? RiskPreferenceWire.parse(risk)
          : RiskPreference.moderate,
      accounts: accountsRaw is Map
          ? AccountSummary.fromJson(_strKeyed(accountsRaw))
          : const AccountSummary(totalCount: 0, byKind: <String, int>{}),
      cashflow: cashflowRaw is Map
          ? CashflowSummary.fromJson(_strKeyed(cashflowRaw))
          : const CashflowSummary(
              baseCurrency: 'USD',
              monthsCovered: 0,
              averageInflowMinor: '0',
              averageOutflowMinor: '0',
              trend: CashflowTrend.unknown,
            ),
      fireGoal: fireRaw is Map
          ? FireGoalSummary.fromJson(_strKeyed(fireRaw))
          : null,
    );
  }
}

Map<String, Object?> _strKeyed(Map<Object?, Object?> raw) =>
    raw.map((k, v) => MapEntry(k.toString(), v));
