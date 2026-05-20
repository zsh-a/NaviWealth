import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/domain/values/money.dart';
import 'package:naviwealth/features/fire/domain/fire_action.dart';
import 'package:naviwealth/features/fire/domain/fire_goal.dart';
import 'package:naviwealth/features/fire/domain/fire_plan.dart';
import 'package:naviwealth/features/fire/domain/fire_state.dart';
import 'package:naviwealth/features/fire/domain/fire_state_service.dart';

void main() {
  group('computeFireState', () {
    final fixedNow = DateTime.utc(2026, 5, 20);

    FirePlan plan({
      String targetNetWorth = '1000000',
      String monthlyExpenses = '4000',
      String monthlySurplus = '5000',
      double swr = 0.04,
      int cashBucketMonths = 12,
    }) {
      return FirePlan.fromGoal(
        FireGoal(
          targetAmount: Decimal.parse(targetNetWorth),
          monthlyExpenses: Decimal.parse(monthlyExpenses),
          monthlySurplus: Decimal.parse(monthlySurplus),
          inflationRate: 0.03,
        ),
        baseCurrency: 'CNY',
        safeWithdrawalRate: swr,
        targetCashBucketMonths: cashBucketMonths,
      );
    }

    test('unconfigured plan → unconfigured safety level + configure action', () {
      final state = computeFireState(
        plan: FirePlan.unset(baseCurrency: 'CNY'),
        netWorth: Money.zero('CNY'),
        investableAssets: Money.zero('CNY'),
        liquidAssets: Money.zero('CNY'),
        trailingAnnualSpend: null,
        fireEtaMonths: null,
        currencyMismatchCount: 0,
        computedAt: fixedNow,
      );
      expect(state.safetyLevel, FireSafetyLevel.unconfigured);
      expect(state.suggestedActions, hasLength(1));
      expect(
        state.suggestedActions.first.kind,
        FireActionKind.configurePlan,
      );
      expect(state.fireEtaMonths, isNull);
    });

    test('healthy plan with low WR + full cash bucket → safe + holdSteady', () {
      // Investable 2_000_000 CNY, annual spend 48_000 → WR 2.4%, below 4% SWR.
      // Liquid 48_000 = exactly 12 months of expenses → on target.
      final state = computeFireState(
        plan: plan(),
        netWorth: Money(Decimal.parse('2000000'), 'CNY'),
        investableAssets: Money(Decimal.parse('2000000'), 'CNY'),
        liquidAssets: Money(Decimal.parse('48000'), 'CNY'),
        trailingAnnualSpend: null,
        fireEtaMonths: 60,
        currencyMismatchCount: 0,
        computedAt: fixedNow,
      );
      expect(state.safetyLevel, FireSafetyLevel.safe);
      expect(state.withdrawalRate, closeTo(0.024, 1e-6));
      expect(state.cashBucketMonths, closeTo(12, 1e-6));
      expect(
        state.suggestedActions.map((a) => a.kind).toList(),
        [FireActionKind.holdSteady],
      );
      expect(state.fireEtaMonths, 60);
    });

    test('WR above SWR but ≤ 1.5×SWR → cautious + reduceSpending warning', () {
      // Investable 800_000, annual 48_000 → WR 6%, SWR 4% → cautious (< 6%).
      final state = computeFireState(
        plan: plan(),
        netWorth: Money(Decimal.parse('800000'), 'CNY'),
        investableAssets: Money(Decimal.parse('800000'), 'CNY'),
        liquidAssets: Money(Decimal.parse('60000'), 'CNY'),
        trailingAnnualSpend: null,
        fireEtaMonths: null,
        currencyMismatchCount: 0,
        computedAt: fixedNow,
      );
      expect(state.safetyLevel, FireSafetyLevel.cautious);
      final kinds = state.suggestedActions.map((a) => a.kind).toSet();
      expect(kinds, containsAll([
        FireActionKind.reduceSpending,
        FireActionKind.delayDiscretionary,
      ]));
    });

    test('WR > 1.5×SWR → danger + critical reduceSpending', () {
      // Investable 400_000, annual 48_000 → WR 12% (3× SWR) → danger.
      final state = computeFireState(
        plan: plan(),
        netWorth: Money(Decimal.parse('400000'), 'CNY'),
        investableAssets: Money(Decimal.parse('400000'), 'CNY'),
        liquidAssets: Money(Decimal.parse('48000'), 'CNY'),
        trailingAnnualSpend: null,
        fireEtaMonths: null,
        currencyMismatchCount: 0,
        computedAt: fixedNow,
      );
      expect(state.safetyLevel, FireSafetyLevel.danger);
      expect(
        state.suggestedActions.any(
          (a) =>
              a.kind == FireActionKind.reduceSpending &&
              a.severity == FireActionSeverity.critical,
        ),
        isTrue,
      );
    });

    test('zero investable + non-zero spend → infinity WR + danger', () {
      final state = computeFireState(
        plan: plan(),
        netWorth: Money(Decimal.parse('-10000'), 'CNY'),
        investableAssets: Money.zero('CNY'),
        liquidAssets: Money.zero('CNY'),
        trailingAnnualSpend: null,
        fireEtaMonths: null,
        currencyMismatchCount: 0,
        computedAt: fixedNow,
      );
      expect(state.withdrawalRate.isFinite, isFalse);
      expect(state.safetyLevel, FireSafetyLevel.danger);
      expect(state.finiteWithdrawalRate, isNull);
    });

    test('cash bucket below target → topUpCashBucket action with shortfall',
        () {
      // Monthly expense 4_000, target 12 months = 48_000 cash.
      // Liquid 12_000 → only 3 months → < 50% → critical.
      final state = computeFireState(
        plan: plan(),
        netWorth: Money(Decimal.parse('2000000'), 'CNY'),
        investableAssets: Money(Decimal.parse('2000000'), 'CNY'),
        liquidAssets: Money(Decimal.parse('12000'), 'CNY'),
        trailingAnnualSpend: null,
        fireEtaMonths: null,
        currencyMismatchCount: 0,
        computedAt: fixedNow,
      );
      expect(state.safetyLevel, FireSafetyLevel.danger);
      final topUp = state.suggestedActions.firstWhere(
        (a) => a.kind == FireActionKind.topUpCashBucket,
      );
      expect(topUp.severity, FireActionSeverity.critical);
      expect(topUp.amount, Money(Decimal.parse('36000'), 'CNY'));
      expect(topUp.months, 12);
    });

    test(
        'cash bucket between 50% and 100% → topUpCashBucket warning, not critical',
        () {
      // Liquid 30_000 → 7.5 months / 12 target → 62.5% → warning.
      final state = computeFireState(
        plan: plan(),
        netWorth: Money(Decimal.parse('2000000'), 'CNY'),
        investableAssets: Money(Decimal.parse('2000000'), 'CNY'),
        liquidAssets: Money(Decimal.parse('30000'), 'CNY'),
        trailingAnnualSpend: null,
        fireEtaMonths: null,
        currencyMismatchCount: 0,
        computedAt: fixedNow,
      );
      expect(state.safetyLevel, FireSafetyLevel.cautious);
      final topUp = state.suggestedActions.firstWhere(
        (a) => a.kind == FireActionKind.topUpCashBucket,
      );
      expect(topUp.severity, FireActionSeverity.warning);
    });

    test('trailing-12m annual spend supersedes plan input', () {
      final state = computeFireState(
        plan: plan(monthlyExpenses: '4000'),
        netWorth: Money(Decimal.parse('2000000'), 'CNY'),
        investableAssets: Money(Decimal.parse('2000000'), 'CNY'),
        liquidAssets: Money(Decimal.parse('48000'), 'CNY'),
        trailingAnnualSpend: Money(Decimal.parse('60000'), 'CNY'),
        fireEtaMonths: null,
        currencyMismatchCount: 0,
        computedAt: fixedNow,
      );
      expect(state.annualSpend, Money(Decimal.parse('60000'), 'CNY'));
      expect(state.annualSpendSource, FireAnnualSpendSource.trailing12m);
    });

    test('currency mismatch nudges state from safe to cautious', () {
      final state = computeFireState(
        plan: plan(),
        netWorth: Money(Decimal.parse('2000000'), 'CNY'),
        investableAssets: Money(Decimal.parse('2000000'), 'CNY'),
        liquidAssets: Money(Decimal.parse('48000'), 'CNY'),
        trailingAnnualSpend: null,
        fireEtaMonths: 60,
        currencyMismatchCount: 2,
        computedAt: fixedNow,
      );
      expect(state.safetyLevel, FireSafetyLevel.cautious);
      expect(
        state.suggestedActions.any(
          (a) => a.kind == FireActionKind.fixCurrencyGap && a.months == 2,
        ),
        isTrue,
      );
    });

    test('negative net worth → danger + buildRiskReserve action', () {
      final state = computeFireState(
        plan: plan(),
        netWorth: Money(Decimal.parse('-50000'), 'CNY'),
        investableAssets: Money(Decimal.parse('100000'), 'CNY'),
        liquidAssets: Money(Decimal.parse('48000'), 'CNY'),
        trailingAnnualSpend: null,
        fireEtaMonths: null,
        currencyMismatchCount: 0,
        computedAt: fixedNow,
      );
      expect(state.safetyLevel, FireSafetyLevel.danger);
      expect(
        state.suggestedActions.any(
          (a) => a.kind == FireActionKind.buildRiskReserve,
        ),
        isTrue,
      );
    });

    test('rejects mismatched currency inputs', () {
      expect(
        () => computeFireState(
          plan: plan(),
          netWorth: Money(Decimal.parse('1'), 'USD'),
          investableAssets: Money.zero('CNY'),
          liquidAssets: Money.zero('CNY'),
          trailingAnnualSpend: null,
          fireEtaMonths: null,
          currencyMismatchCount: 0,
          computedAt: fixedNow,
        ),
        throwsArgumentError,
      );
    });

    test('toJson is stable, omits infinity, includes structured actions', () {
      final state = computeFireState(
        plan: plan(),
        netWorth: Money(Decimal.parse('2000000'), 'CNY'),
        investableAssets: Money(Decimal.parse('2000000'), 'CNY'),
        liquidAssets: Money(Decimal.parse('48000'), 'CNY'),
        trailingAnnualSpend: null,
        fireEtaMonths: 60,
        currencyMismatchCount: 0,
        computedAt: fixedNow,
      );
      final json = state.toJson();
      expect(json['safety_level'], 'safe');
      expect(json['base_currency'], 'CNY');
      expect(json['target_cash_bucket_months'], 12);
      expect(json['safe_withdrawal_rate'], 0.04);
      expect(json['suggested_actions'], isA<List<Object?>>());
    });
  });
}
