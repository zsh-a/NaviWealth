import 'package:flutter/foundation.dart';

import 'package:naviwealth/domain/values/money.dart';
import 'fire_action.dart';
import 'fire_state.dart';

/// Periodic cadence the review covers.
///
/// Codes are persisted in the review cache and the AI tool output —
/// don't rename after shipping.
enum FireReviewKind { monthly, quarterly, annual }

/// One observation inside a review — a verdict + an l10n-ready code
/// the UI / AI resolve into copy. `params` carries the numbers the
/// observation refers to (current WR, target months, etc.) so renders
/// stay localised without coupling the engine to copy.
enum FireReviewFindingCode {
  withinTargetCashBucket,
  belowTargetCashBucket,
  withdrawalRateBelowSwr,
  withdrawalRateAboveSwr,
  withdrawalRateInfinite,
  fireEtaReached,
  fireEtaUnreachable,
  fireEtaProgressing,
  unmappedHoldingsPresent,
  currencyGapPresent,
  stressTestDanger,
  stressTestCautious,
  stressTestSafe,
  netWorthBroken,
  netWorthHealthy,
}

@immutable
class FireReviewFinding {
  const FireReviewFinding({
    required this.code,
    required this.severity,
    this.amount,
    this.months,
    this.pct,
    this.scenarioCode,
  });

  final FireReviewFindingCode code;
  final FireActionSeverity severity;
  final Money? amount;
  final int? months;
  final double? pct;

  /// Wire-name of the stress scenario this finding refers to, when
  /// applicable (e.g. `market_drawdown`). Lets the UI/AI link the
  /// finding back to the offending stress row.
  final String? scenarioCode;

  Map<String, Object?> toJson() => <String, Object?>{
    'code': code.name,
    'severity': severity.name,
    if (amount != null) ...{
      'amount': amount!.amount.toString(),
      'currency': amount!.currency,
    },
    if (months != null) 'months': months,
    if (pct != null) 'pct': pct,
    if (scenarioCode != null) 'scenario': scenarioCode,
  };

  @override
  bool operator ==(Object other) =>
      other is FireReviewFinding &&
      other.code == code &&
      other.severity == severity &&
      other.amount == amount &&
      other.months == months &&
      other.pct == pct &&
      other.scenarioCode == scenarioCode;

  @override
  int get hashCode =>
      Object.hash(code, severity, amount, months, pct, scenarioCode);
}

/// A self-contained periodic review.
///
/// Deterministic: identical inputs produce identical reviews. AI may
/// explain a review, but never invent its metrics or findings —
/// `generateReview` is the source of truth.
@immutable
class FireReview {
  const FireReview({
    required this.kind,
    required this.periodKey,
    required this.generatedAt,
    required this.baseCurrency,
    required this.safetyLevel,
    required this.netWorth,
    required this.investableAssets,
    required this.liquidAssets,
    required this.annualSpend,
    required this.withdrawalRate,
    required this.safeWithdrawalRate,
    required this.cashBucketMonths,
    required this.targetCashBucketMonths,
    required this.fireEtaMonths,
    required this.findings,
    required this.suggestedActions,
  });

  final FireReviewKind kind;

  /// `yyyy-MM` for monthly, `yyyy-Q[1-4]` for quarterly, `yyyy` for
  /// annual. The cache keys reviews by this string so a regenerated
  /// review for the same period overwrites the prior one in place.
  final String periodKey;

  final DateTime generatedAt;
  final String baseCurrency;

  final FireSafetyLevel safetyLevel;
  final Money netWorth;
  final Money investableAssets;
  final Money liquidAssets;
  final Money annualSpend;

  /// May be infinite — consumers gate on `.isFinite`.
  final double withdrawalRate;
  final double safeWithdrawalRate;

  final double cashBucketMonths;
  final int targetCashBucketMonths;

  final int? fireEtaMonths;

  final List<FireReviewFinding> findings;
  final List<FireAction> suggestedActions;

  Map<String, Object?> toJson() {
    double? finite(double v) => v.isFinite ? v : null;
    return <String, Object?>{
      'kind': kind.name,
      'period_key': periodKey,
      'generated_at': generatedAt.toUtc().toIso8601String(),
      'base_currency': baseCurrency,
      'safety_level': safetyLevel.name,
      'net_worth': netWorth.amount.toString(),
      'investable_assets': investableAssets.amount.toString(),
      'liquid_assets': liquidAssets.amount.toString(),
      'annual_spend': annualSpend.amount.toString(),
      'withdrawal_rate': finite(withdrawalRate),
      'safe_withdrawal_rate': safeWithdrawalRate,
      'cash_bucket_months': finite(cashBucketMonths),
      'target_cash_bucket_months': targetCashBucketMonths,
      'fire_eta_months': fireEtaMonths,
      'findings': findings.map((f) => f.toJson()).toList(growable: false),
      'suggested_actions': suggestedActions
          .map((a) => a.toJson())
          .toList(growable: false),
    };
  }

  factory FireReview.fromJson(Map<String, Object?> json) {
    final base = json['base_currency'] as String? ?? 'CNY';
    Money m(Object? value) {
      final raw = value?.toString() ?? '0';
      return Money.parse(raw, base);
    }

    final findings = <FireReviewFinding>[];
    final rawFindings = json['findings'];
    if (rawFindings is List) {
      for (final f in rawFindings) {
        if (f is! Map) continue;
        final m = Map<String, Object?>.from(f);
        findings.add(
          FireReviewFinding(
            code: FireReviewFindingCode.values.firstWhere(
              (c) => c.name == m['code'],
              orElse: () => FireReviewFindingCode.withinTargetCashBucket,
            ),
            severity: FireActionSeverity.values.firstWhere(
              (s) => s.name == m['severity'],
              orElse: () => FireActionSeverity.info,
            ),
            months: (m['months'] as num?)?.toInt(),
            pct: (m['pct'] as num?)?.toDouble(),
            scenarioCode: m['scenario'] as String?,
          ),
        );
      }
    }
    return FireReview(
      kind: FireReviewKind.values.firstWhere(
        (k) => k.name == json['kind'],
        orElse: () => FireReviewKind.monthly,
      ),
      periodKey: json['period_key'] as String? ?? '',
      generatedAt:
          DateTime.tryParse(json['generated_at'] as String? ?? '') ??
          DateTime.now().toUtc(),
      baseCurrency: base,
      safetyLevel: FireSafetyLevel.values.firstWhere(
        (s) => s.name == json['safety_level'],
        orElse: () => FireSafetyLevel.unconfigured,
      ),
      netWorth: m(json['net_worth']),
      investableAssets: m(json['investable_assets']),
      liquidAssets: m(json['liquid_assets']),
      annualSpend: m(json['annual_spend']),
      withdrawalRate:
          (json['withdrawal_rate'] as num?)?.toDouble() ?? double.nan,
      safeWithdrawalRate:
          (json['safe_withdrawal_rate'] as num?)?.toDouble() ?? 0.04,
      cashBucketMonths:
          (json['cash_bucket_months'] as num?)?.toDouble() ?? double.nan,
      targetCashBucketMonths:
          (json['target_cash_bucket_months'] as num?)?.toInt() ?? 12,
      fireEtaMonths: (json['fire_eta_months'] as num?)?.toInt(),
      findings: findings,
      suggestedActions: const <FireAction>[],
    );
  }
}
