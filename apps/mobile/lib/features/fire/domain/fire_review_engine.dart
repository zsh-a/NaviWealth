import 'package:decimal/decimal.dart';

import 'fire_action.dart';
import 'fire_bucket.dart';
import 'fire_review.dart';
import 'fire_state.dart';
import 'fire_stress_test.dart';

/// Build a periodic review from a [FireState] and (optionally) the
/// freshly-computed stress results.
///
/// Pure: no providers, no LLM. Every finding is derivable from the
/// inputs; the AI tool layer (Phase 5) reads the resulting [FireReview]
/// and renders an explanation, but never invents metrics.
FireReview generateReview({
  required FireReviewKind kind,
  required FireState state,
  List<FireStressResult> stressTests = const <FireStressResult>[],
  DateTime? now,
}) {
  final at = (now ?? DateTime.now()).toUtc();
  final periodKey = _periodKey(at, kind);

  final findings = _findings(state, stressTests);

  return FireReview(
    kind: kind,
    periodKey: periodKey,
    generatedAt: at,
    baseCurrency: state.baseCurrency,
    safetyLevel: state.safetyLevel,
    netWorth: state.netWorth,
    investableAssets: state.investableAssets,
    liquidAssets: state.liquidAssets,
    annualSpend: state.annualSpend,
    withdrawalRate: state.withdrawalRate,
    safeWithdrawalRate: state.plan.safeWithdrawalRate,
    cashBucketMonths: state.cashBucketMonths,
    targetCashBucketMonths: state.plan.targetCashBucketMonths,
    fireEtaMonths: state.fireEtaMonths,
    findings: findings,
    suggestedActions: state.suggestedActions,
  );
}

String _periodKey(DateTime at, FireReviewKind kind) {
  final y = at.year.toString().padLeft(4, '0');
  switch (kind) {
    case FireReviewKind.monthly:
      return '$y-${at.month.toString().padLeft(2, '0')}';
    case FireReviewKind.quarterly:
      final q = ((at.month - 1) ~/ 3) + 1;
      return '$y-Q$q';
    case FireReviewKind.annual:
      return y;
  }
}

List<FireReviewFinding> _findings(
  FireState state,
  List<FireStressResult> stressTests,
) {
  final findings = <FireReviewFinding>[];

  // Net worth.
  if (state.netWorth.amount <= Decimal.zero) {
    findings.add(
      const FireReviewFinding(
        code: FireReviewFindingCode.netWorthBroken,
        severity: FireActionSeverity.critical,
      ),
    );
  } else {
    findings.add(
      const FireReviewFinding(
        code: FireReviewFindingCode.netWorthHealthy,
        severity: FireActionSeverity.info,
      ),
    );
  }

  // Withdrawal rate.
  if (!state.withdrawalRate.isFinite) {
    findings.add(
      const FireReviewFinding(
        code: FireReviewFindingCode.withdrawalRateInfinite,
        severity: FireActionSeverity.critical,
      ),
    );
  } else if (state.withdrawalRate > state.plan.safeWithdrawalRate) {
    findings.add(
      FireReviewFinding(
        code: FireReviewFindingCode.withdrawalRateAboveSwr,
        severity: state.withdrawalRate >
                state.plan.safeWithdrawalRate * 1.5
            ? FireActionSeverity.critical
            : FireActionSeverity.warning,
        pct: state.withdrawalRate - state.plan.safeWithdrawalRate,
      ),
    );
  } else {
    findings.add(
      FireReviewFinding(
        code: FireReviewFindingCode.withdrawalRateBelowSwr,
        severity: FireActionSeverity.info,
        pct: state.plan.safeWithdrawalRate - state.withdrawalRate,
      ),
    );
  }

  // Cash bucket.
  if (state.cashBucketMonths < state.plan.targetCashBucketMonths) {
    findings.add(
      FireReviewFinding(
        code: FireReviewFindingCode.belowTargetCashBucket,
        severity: state.cashBucketMonths <
                state.plan.targetCashBucketMonths * 0.5
            ? FireActionSeverity.critical
            : FireActionSeverity.warning,
        months: state.plan.targetCashBucketMonths,
      ),
    );
  } else {
    findings.add(
      FireReviewFinding(
        code: FireReviewFindingCode.withinTargetCashBucket,
        severity: FireActionSeverity.info,
        months: state.plan.targetCashBucketMonths,
      ),
    );
  }

  // FIRE ETA.
  if (state.fireEtaMonths == null) {
    findings.add(
      const FireReviewFinding(
        code: FireReviewFindingCode.fireEtaUnreachable,
        severity: FireActionSeverity.warning,
      ),
    );
  } else if (state.fireEtaMonths == 0) {
    findings.add(
      const FireReviewFinding(
        code: FireReviewFindingCode.fireEtaReached,
        severity: FireActionSeverity.info,
      ),
    );
  } else {
    findings.add(
      FireReviewFinding(
        code: FireReviewFindingCode.fireEtaProgressing,
        severity: FireActionSeverity.info,
        months: state.fireEtaMonths,
      ),
    );
  }

  // FX / unmapped surfaces.
  if (state.currencyMismatchCount > 0) {
    findings.add(
      FireReviewFinding(
        code: FireReviewFindingCode.currencyGapPresent,
        severity: FireActionSeverity.warning,
        months: state.currencyMismatchCount,
      ),
    );
  }
  if (state.unmappedHoldings.isNotEmpty) {
    findings.add(
      FireReviewFinding(
        code: FireReviewFindingCode.unmappedHoldingsPresent,
        severity: FireActionSeverity.info,
        months: state.unmappedHoldings.length,
      ),
    );
  }

  // Stress test summaries.
  for (final r in stressTests) {
    switch (r.verdict) {
      case FireStressVerdict.danger:
        findings.add(
          FireReviewFinding(
            code: FireReviewFindingCode.stressTestDanger,
            severity: FireActionSeverity.critical,
            scenarioCode: _scenarioCode(r),
          ),
        );
      case FireStressVerdict.cautious:
        findings.add(
          FireReviewFinding(
            code: FireReviewFindingCode.stressTestCautious,
            severity: FireActionSeverity.warning,
            scenarioCode: _scenarioCode(r),
          ),
        );
      case FireStressVerdict.safe:
        // Surface a single `safe` finding rather than five per scenario;
        // emit per-scenario "safe" only when there are no concerning
        // peers — keeps the report's signal density high.
        break;
    }
  }
  if (stressTests.isNotEmpty &&
      stressTests.every((r) => r.verdict == FireStressVerdict.safe)) {
    findings.add(
      const FireReviewFinding(
        code: FireReviewFindingCode.stressTestSafe,
        severity: FireActionSeverity.info,
      ),
    );
  }

  return List.unmodifiable(findings);
}

String _scenarioCode(FireStressResult r) {
  // Mirror the snake-case wire code from `FireStressResult.toJson()`.
  return r.toJson()['scenario'] as String;
}

/// Bucket-by-bucket diff between two reviews. Useful for the
/// "what changed" callout in the UI and the AI explanation prompt.
class FireReviewDiff {
  const FireReviewDiff({
    required this.before,
    required this.after,
  });

  final FireReview? before;
  final FireReview after;

  /// How [after]'s withdrawal rate compares to [before]'s. `null` when
  /// either side is infinite or there is no prior.
  double? get withdrawalRateDelta {
    final b = before?.withdrawalRate;
    if (b == null || !b.isFinite || !after.withdrawalRate.isFinite) {
      return null;
    }
    return after.withdrawalRate - b;
  }

  /// Net-worth delta (after − before), in the after currency. `null`
  /// when there is no prior, or the currencies differ (we don't FX-
  /// convert across reviews — that responsibility lives upstream).
  ///
  /// Returns a [Decimal] rather than [Money] because the call site is
  /// just rendering a "+¥X" delta; carrying a full Money object adds
  /// nothing here.
  Decimal? get netWorthDelta {
    if (before == null) return null;
    if (before!.baseCurrency != after.baseCurrency) return null;
    return after.netWorth.amount - before!.netWorth.amount;
  }

  /// Did the headline safety level change?
  bool get safetyLevelChanged =>
      before != null && before!.safetyLevel != after.safetyLevel;

  /// Did the bucket coverage status change for any of the five roles?
  /// Phase 4 doesn't ship per-bucket diff yet because buckets are
  /// computed from the snapshot and not persisted with the review.
  bool bucketStatusChangedFor(FireBucketRole _) => false;
}
