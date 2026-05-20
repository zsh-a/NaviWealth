import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/domain/values/money.dart';
import 'package:naviwealth/features/fire/domain/fire_action.dart';
import 'package:naviwealth/features/fire/domain/fire_goal.dart';
import 'package:naviwealth/features/fire/domain/fire_plan.dart';
import 'package:naviwealth/features/fire/domain/fire_review.dart';
import 'package:naviwealth/features/fire/domain/fire_review_engine.dart';
import 'package:naviwealth/features/fire/domain/fire_state.dart';
import 'package:naviwealth/features/fire/domain/fire_state_service.dart';
import 'package:naviwealth/features/fire/domain/fire_stress_test_engine.dart';

FireState _state({
  String investable = '2000000',
  String liquid = '48000',
  String annualSpend = '48000',
  String netWorth = '2000000',
  int currencyMismatch = 0,
  int? etaMonths = 60,
}) {
  final plan = FirePlan.fromGoal(
    FireGoal(
      targetAmount: Decimal.parse('1000000'),
      monthlyExpenses: Decimal.parse('4000'),
      monthlySurplus: Decimal.zero,
      inflationRate: 0,
    ),
    baseCurrency: 'CNY',
    safeWithdrawalRate: 0.04,
    targetCashBucketMonths: 12,
  );
  return computeFireState(
    plan: plan,
    netWorth: Money(Decimal.parse(netWorth), 'CNY'),
    investableAssets: Money(Decimal.parse(investable), 'CNY'),
    liquidAssets: Money(Decimal.parse(liquid), 'CNY'),
    trailingAnnualSpend: Money(Decimal.parse(annualSpend), 'CNY'),
    fireEtaMonths: etaMonths,
    currencyMismatchCount: currencyMismatch,
    computedAt: DateTime.utc(2026, 5, 20),
  );
}

void main() {
  group('generateReview', () {
    test('produces deterministic output (same inputs → same review)', () {
      final state = _state();
      final stress = runStressTests(state);
      final a = generateReview(
        kind: FireReviewKind.monthly,
        state: state,
        stressTests: stress,
        now: DateTime.utc(2026, 5, 20),
      );
      final b = generateReview(
        kind: FireReviewKind.monthly,
        state: state,
        stressTests: stress,
        now: DateTime.utc(2026, 5, 20),
      );
      expect(a.toJson(), b.toJson());
    });

    test('period key formats by cadence', () {
      final at = DateTime.utc(2026, 7, 15);
      expect(
        generateReview(
          kind: FireReviewKind.monthly,
          state: _state(),
          now: at,
        ).periodKey,
        '2026-07',
      );
      expect(
        generateReview(
          kind: FireReviewKind.quarterly,
          state: _state(),
          now: at,
        ).periodKey,
        '2026-Q3',
      );
      expect(
        generateReview(
          kind: FireReviewKind.annual,
          state: _state(),
          now: at,
        ).periodKey,
        '2026',
      );
    });

    test('healthy plan surfaces info-level findings only', () {
      final state = _state();
      final review = generateReview(
        kind: FireReviewKind.monthly,
        state: state,
        now: DateTime.utc(2026, 5, 20),
      );
      // No critical findings expected.
      expect(
        review.findings.any(
          (f) => f.severity == FireActionSeverity.critical,
        ),
        isFalse,
      );
      // Healthy net worth + below SWR + within target cash + ETA all
      // surface as their info / "good" codes.
      final codes = review.findings.map((f) => f.code).toSet();
      expect(codes, contains(FireReviewFindingCode.netWorthHealthy));
      expect(codes, contains(FireReviewFindingCode.withdrawalRateBelowSwr));
      expect(codes, contains(FireReviewFindingCode.withinTargetCashBucket));
      expect(codes, contains(FireReviewFindingCode.fireEtaProgressing));
    });

    test('broken plan emits critical findings + reports stress dangers',
        () {
      final state = _state(
        investable: '0',
        liquid: '0',
        netWorth: '-50000',
        annualSpend: '48000',
        etaMonths: null,
      );
      final stress = runStressTests(state);
      final review = generateReview(
        kind: FireReviewKind.monthly,
        state: state,
        stressTests: stress,
        now: DateTime.utc(2026, 5, 20),
      );
      final codes = review.findings.map((f) => f.code).toList();
      expect(codes, contains(FireReviewFindingCode.netWorthBroken));
      expect(codes, contains(FireReviewFindingCode.withdrawalRateInfinite));
      expect(codes, contains(FireReviewFindingCode.fireEtaUnreachable));
      // At least one stress danger finding referencing a scenario code.
      final dangers = review.findings
          .where((f) => f.code == FireReviewFindingCode.stressTestDanger)
          .toList();
      expect(dangers, isNotEmpty);
      expect(dangers.first.scenarioCode, isNotNull);
    });

    test('all-safe stress collapses to a single safe finding', () {
      final state = _state();
      final stress = runStressTests(state);
      final review = generateReview(
        kind: FireReviewKind.monthly,
        state: state,
        stressTests: stress,
        now: DateTime.utc(2026, 5, 20),
      );
      // If every scenario is safe the engine emits exactly one
      // `stressTestSafe` rollup, not five.
      final allSafe = stress.every((r) => r.verdict.name == 'safe');
      if (allSafe) {
        final safe = review.findings
            .where((f) => f.code == FireReviewFindingCode.stressTestSafe)
            .toList();
        expect(safe, hasLength(1));
      }
    });

    test('currency mismatches and unmapped holdings surface as findings',
        () {
      final state = _state(currencyMismatch: 2);
      final review = generateReview(
        kind: FireReviewKind.monthly,
        state: state,
        now: DateTime.utc(2026, 5, 20),
      );
      final fxFinding = review.findings.firstWhere(
        (f) => f.code == FireReviewFindingCode.currencyGapPresent,
      );
      expect(fxFinding.months, 2);
    });

    test('toJson / fromJson round-trip preserves the headline metrics', () {
      final state = _state();
      final stress = runStressTests(state);
      final review = generateReview(
        kind: FireReviewKind.monthly,
        state: state,
        stressTests: stress,
        now: DateTime.utc(2026, 5, 20),
      );
      final decoded = FireReview.fromJson(review.toJson());
      expect(decoded.kind, review.kind);
      expect(decoded.periodKey, review.periodKey);
      expect(decoded.safetyLevel, review.safetyLevel);
      expect(decoded.netWorth, review.netWorth);
      expect(decoded.withdrawalRate, review.withdrawalRate);
      expect(decoded.targetCashBucketMonths, review.targetCashBucketMonths);
      expect(decoded.findings.length, review.findings.length);
    });
  });
}
