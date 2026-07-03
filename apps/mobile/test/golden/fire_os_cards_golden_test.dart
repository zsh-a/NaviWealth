import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naviwealth/features/finance/application/read_models/dashboard_providers.dart';
import 'package:naviwealth/features/finance/domain/fx/money.dart';
import 'package:naviwealth/features/finance/fire/data/fire_providers.dart';
import 'package:naviwealth/features/finance/fire/domain/fire_action.dart';
import 'package:naviwealth/features/finance/fire/domain/fire_bucket.dart';
import 'package:naviwealth/features/finance/fire/domain/fire_bucket_allocator.dart';
import 'package:naviwealth/features/finance/fire/domain/fire_goal.dart';
import 'package:naviwealth/features/finance/fire/domain/fire_plan.dart';
import 'package:naviwealth/features/finance/fire/domain/fire_state.dart';
import 'package:naviwealth/features/finance/fire/domain/fire_stress_test.dart';
import 'package:naviwealth/features/finance/fire/ui/fire_buckets_card.dart';
import 'package:naviwealth/features/finance/fire/ui/fire_state_hero_card.dart';
import 'package:naviwealth/features/finance/fire/ui/fire_stress_tests_card.dart';
import 'package:naviwealth/features/finance/home/domain/dashboard_models.dart';

import '_golden_setup.dart';

FireState _stubState() {
  final plan = FirePlan.fromGoal(
    FireGoal(
      targetAmount: Decimal.parse('1000000'),
      monthlyExpenses: Decimal.parse('4000'),
      monthlySurplus: Decimal.parse('5000'),
      inflationRate: 0.03,
    ),
    baseCurrency: 'CNY',
  );
  return FireState(
    plan: plan,
    baseCurrency: 'CNY',
    netWorth: Money(Decimal.parse('820000'), 'CNY'),
    investableAssets: Money(Decimal.parse('780000'), 'CNY'),
    liquidAssets: Money(Decimal.parse('36000'), 'CNY'),
    annualSpend: Money(Decimal.parse('48000'), 'CNY'),
    monthlyExpense: Money(Decimal.parse('4000'), 'CNY'),
    withdrawalRate: 0.0615,
    cashBucketMonths: 9.0,
    fireEtaMonths: 84,
    safetyLevel: FireSafetyLevel.cautious,
    suggestedActions: const [
      FireAction(
        kind: FireActionKind.topUpCashBucket,
        severity: FireActionSeverity.warning,
        months: 12,
      ),
      FireAction(
        kind: FireActionKind.reduceSpending,
        severity: FireActionSeverity.warning,
        pct: 0.0215,
      ),
    ],
    buckets: const [],
    stressTests: const [],
    currencyMismatchCount: 0,
    computedAt: DateTime.utc(2026, 5, 20),
  );
}

FireBucketAllocation _stubAllocation() {
  return FireBucketAllocation(
    buckets: [
      FireBucketState(
        role: FireBucketRole.cash,
        currentValue: Money(Decimal.parse('36000'), 'CNY'),
        targetValue: Money(Decimal.parse('48000'), 'CNY'),
        status: FireBucketStatus.underTarget,
        coverageRatio: 0.75,
        assetIds: const ['cash-1', 'cash-2'],
      ),
      FireBucketState(
        role: FireBucketRole.defensive,
        currentValue: Money(Decimal.parse('60000'), 'CNY'),
        targetValue: Money.zero('CNY'),
        status: FireBucketStatus.onTrack,
        coverageRatio: null,
        assetIds: const ['bond-1'],
      ),
      FireBucketState(
        role: FireBucketRole.growth,
        currentValue: Money(Decimal.parse('660000'), 'CNY'),
        targetValue: Money.zero('CNY'),
        status: FireBucketStatus.onTrack,
        coverageRatio: null,
        assetIds: const ['etf-qqq', 'etf-voo'],
      ),
      FireBucketState(
        role: FireBucketRole.riskReserve,
        currentValue: Money.zero('CNY'),
        targetValue: Money.zero('CNY'),
        status: FireBucketStatus.empty,
        coverageRatio: null,
        assetIds: const [],
      ),
      FireBucketState(
        role: FireBucketRole.dream,
        currentValue: Money.zero('CNY'),
        targetValue: Money.zero('CNY'),
        status: FireBucketStatus.empty,
        coverageRatio: null,
        assetIds: const [],
      ),
    ],
    unmappedHoldings: [
      FireUnmappedHolding(
        id: 'house',
        name: 'Primary residence',
        value: Money.parse('1500000', 'CNY'),
        reason: 'category_not_drawable',
      ),
    ],
  );
}

DashboardSnapshot _stubSnapshot() {
  return DashboardSnapshot.empty(
    asOf: DateTime.utc(2026, 5, 20),
    baseCurrency: 'CNY',
  );
}

List<FireStressResult> _stubStress() {
  Money m(String n) => Money(Decimal.parse(n), 'CNY');
  return [
    FireStressResult(
      scenario: FireStressScenario.marketDrawdown,
      verdict: FireStressVerdict.cautious,
      params: const FireStressParams(drawdownPct: 0.35),
      netWorthAfter: m('547000'),
      investableAssetsAfter: m('507000'),
      annualSpendAfter: m('48000'),
      withdrawalRateAfter: 0.0947,
      cashBucketMonthsAfter: 9.0,
      recommendedActions: const [],
    ),
    FireStressResult(
      scenario: FireStressScenario.expenseSurge,
      verdict: FireStressVerdict.danger,
      params: const FireStressParams(expenseShockPct: 0.20),
      netWorthAfter: m('820000'),
      investableAssetsAfter: m('780000'),
      annualSpendAfter: m('57600'),
      withdrawalRateAfter: 0.0738,
      cashBucketMonthsAfter: 7.5,
      recommendedActions: const [],
    ),
    FireStressResult(
      scenario: FireStressScenario.oneOffShock,
      verdict: FireStressVerdict.safe,
      params: const FireStressParams(amount: 0),
      netWorthAfter: m('820000'),
      investableAssetsAfter: m('780000'),
      annualSpendAfter: m('48000'),
      withdrawalRateAfter: 0.0615,
      cashBucketMonthsAfter: 9.0,
      recommendedActions: const [],
    ),
    FireStressResult(
      scenario: FireStressScenario.fxShock,
      verdict: FireStressVerdict.safe,
      params: const FireStressParams(fxShockPct: 0.10),
      netWorthAfter: m('742000'),
      investableAssetsAfter: m('702000'),
      annualSpendAfter: m('48000'),
      withdrawalRateAfter: 0.0684,
      cashBucketMonthsAfter: 9.0,
      recommendedActions: const [],
    ),
    FireStressResult(
      scenario: FireStressScenario.cashDepletion,
      verdict: FireStressVerdict.safe,
      params: const FireStressParams(months: 12),
      netWorthAfter: m('820000'),
      investableAssetsAfter: m('780000'),
      annualSpendAfter: m('48000'),
      withdrawalRateAfter: 0.0615,
      cashBucketMonthsAfter: 0.0,
      recommendedActions: const [],
    ),
  ];
}

Widget _wrapCard(Widget card) {
  return Padding(
    padding: const EdgeInsets.all(16),
    child: SingleChildScrollView(child: card),
  );
}

void main() {
  runAllVariants('fire_os_hero', (tester, variant) async {
    await pumpAndSnapshotMobile(
      tester,
      name: 'fire_os_hero',
      variant: variant,
      overrides: [
        fireStateProvider.overrideWith((ref) => AsyncValue.data(_stubState())),
      ],
      child: _wrapCard(const FireStateHeroCard()),
    );
  });

  runAllVariants('fire_os_buckets', (tester, variant) async {
    await pumpAndSnapshotMobile(
      tester,
      name: 'fire_os_buckets',
      variant: variant,
      overrides: [
        fireBucketAllocationProvider.overrideWith(
          (ref) => AsyncValue.data(_stubAllocation()),
        ),
        dashboardSnapshotProvider.overrideWith((ref) async => _stubSnapshot()),
      ],
      child: _wrapCard(const FireBucketsCard()),
    );
  });

  runAllVariants('fire_os_stress', (tester, variant) async {
    await pumpAndSnapshotMobile(
      tester,
      name: 'fire_os_stress',
      variant: variant,
      overrides: [
        fireStressTestsProvider.overrideWith(
          (ref) => AsyncValue.data(_stubStress()),
        ),
      ],
      child: _wrapCard(const FireStressTestsCard()),
    );
  });
}
