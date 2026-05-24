import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/domain/values/money.dart';
import 'package:naviwealth/features/fire/domain/fire_goal.dart';
import 'package:naviwealth/features/fire/domain/fire_plan.dart';

void main() {
  group('FirePlan', () {
    test('unset is unconfigured with sensible defaults', () {
      final plan = FirePlan.unset();
      expect(plan.isConfigured, isFalse);
      expect(plan.safeWithdrawalRate, FirePlan.defaultSafeWithdrawalRate);
      expect(plan.targetCashBucketMonths, FirePlan.defaultCashBucketMonths);
      expect(plan.lifestyleMode, FireLifestyleMode.standard);
      expect(plan.reserves, isEmpty);
    });

    test('fromGoal lifts a configured FireGoal into a FirePlan superset', () {
      final goal = FireGoal(
        targetAmount: Decimal.parse('1000000'),
        monthlyExpenses: Decimal.parse('4000'),
        monthlySurplus: Decimal.parse('5000'),
        inflationRate: 0.03,
      );
      final plan = FirePlan.fromGoal(goal, baseCurrency: 'CNY');
      expect(plan.isConfigured, isTrue);
      expect(plan.baseCurrency, 'CNY');
      expect(plan.targetNetWorth, Decimal.parse('1000000'));
      expect(plan.monthlyExpenses, Decimal.parse('4000'));
      expect(plan.monthlySurplus, Decimal.parse('5000'));
      expect(plan.inflationRate, 0.03);
    });

    test('annualExpense is monthlyExpenses × 12', () {
      final plan = FirePlan.fromGoal(
        FireGoal(
          targetAmount: Decimal.parse('1000000'),
          monthlyExpenses: Decimal.parse('4000'),
          monthlySurplus: Decimal.zero,
          inflationRate: 0,
        ),
        baseCurrency: 'CNY',
      );
      expect(plan.annualExpense, Money(Decimal.parse('48000'), 'CNY'));
    });

    test('toGoal round-trips the shared planning fields', () {
      final goal = FireGoal(
        targetAmount: Decimal.parse('800000'),
        monthlyExpenses: Decimal.parse('3500'),
        monthlySurplus: Decimal.parse('4500'),
        inflationRate: 0.025,
      );
      final plan = FirePlan.fromGoal(goal, baseCurrency: 'CNY');
      expect(plan.toGoal(), goal);
    });

    test('copyWith overrides only the supplied fields', () {
      final plan = FirePlan.fromGoal(
        FireGoal(
          targetAmount: Decimal.parse('1000000'),
          monthlyExpenses: Decimal.parse('4000'),
          monthlySurplus: Decimal.zero,
          inflationRate: 0.03,
        ),
        baseCurrency: 'CNY',
      );
      final updated = plan.copyWith(
        safeWithdrawalRate: 0.035,
        targetCashBucketMonths: 18,
        lifestyleMode: FireLifestyleMode.fat,
      );
      expect(updated.safeWithdrawalRate, 0.035);
      expect(updated.targetCashBucketMonths, 18);
      expect(updated.lifestyleMode, FireLifestyleMode.fat);
      // Untouched fields preserved.
      expect(updated.targetNetWorth, plan.targetNetWorth);
      expect(updated.monthlyExpenses, plan.monthlyExpenses);
    });

    test('totalReserves only sums base-currency reserves', () {
      final plan = FirePlan.fromGoal(
        FireGoal(
          targetAmount: Decimal.parse('1'),
          monthlyExpenses: Decimal.zero,
          monthlySurplus: Decimal.zero,
          inflationRate: 0,
        ),
        baseCurrency: 'CNY',
        reserves: [
          FireReserve(
            id: 'r1',
            label: 'Medical',
            amount: Money(Decimal.parse('50000'), 'CNY'),
            kind: FireReserveKind.medical,
          ),
          FireReserve(
            id: 'r2',
            label: 'Family',
            amount: Money(Decimal.parse('1000'), 'USD'),
            kind: FireReserveKind.family,
          ),
        ],
      );
      expect(plan.totalReserves, Money(Decimal.parse('50000'), 'CNY'));
    });
  });

  group('FireReserve', () {
    test('json round-trip preserves fields', () {
      final reserve = FireReserve(
        id: 'r1',
        label: 'Medical',
        amount: Money(Decimal.parse('30000'), 'CNY'),
        kind: FireReserveKind.medical,
      );
      final decoded = FireReserve.fromJson(reserve.toJson(), 'CNY');
      expect(decoded, reserve);
    });
  });

  group('FireRiskSettings', () {
    test('default settings carry the documented baseline magnitudes', () {
      const settings = FireRiskSettings();
      expect(settings.marketDrawdownPct, 0.35);
      expect(settings.expenseShockPct, 0.20);
      expect(settings.fxShockPct, 0.10);
      expect(settings.oneOffShockAmount, 0);
    });

    test('json round-trip is lossless', () {
      const settings = FireRiskSettings(
        marketDrawdownPct: 0.45,
        expenseShockPct: 0.30,
        fxShockPct: 0.15,
        oneOffShockAmount: 50000,
      );
      final decoded = FireRiskSettings.fromJson(settings.toJson());
      expect(decoded, settings);
    });
  });
}
