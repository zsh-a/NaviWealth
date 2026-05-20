import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/domain/values/money.dart';
import 'package:naviwealth/features/fire/domain/fire_goal.dart';
import 'package:naviwealth/features/fire/domain/fire_plan.dart';
import 'package:naviwealth/features/fire/domain/fire_state.dart';
import 'package:naviwealth/features/fire/domain/fire_state_service.dart';
import 'package:naviwealth/features/fire/domain/fire_stress_test.dart';
import 'package:naviwealth/features/fire/domain/fire_stress_test_engine.dart';

FireState _state({
  String investable = '2000000',
  String liquid = '48000',
  String annualSpend = '48000',
  String netWorth = '2000000',
  double swr = 0.04,
  int cashMonths = 12,
  double drawdown = 0.35,
  double expense = 0.20,
  double fx = 0.10,
  double oneOff = 50000,
  int currencyMismatch = 0,
}) {
  final plan = FirePlan.fromGoal(
    FireGoal(
      targetAmount: Decimal.parse('1000000'),
      monthlyExpenses: Decimal.parse('4000'),
      monthlySurplus: Decimal.zero,
      inflationRate: 0,
    ),
    baseCurrency: 'CNY',
    safeWithdrawalRate: swr,
    targetCashBucketMonths: cashMonths,
    riskSettings: FireRiskSettings(
      marketDrawdownPct: drawdown,
      expenseShockPct: expense,
      fxShockPct: fx,
      oneOffShockAmount: oneOff,
    ),
  );
  return computeFireState(
    plan: plan,
    netWorth: Money(Decimal.parse(netWorth), 'CNY'),
    investableAssets: Money(Decimal.parse(investable), 'CNY'),
    liquidAssets: Money(Decimal.parse(liquid), 'CNY'),
    trailingAnnualSpend: Money(Decimal.parse(annualSpend), 'CNY'),
    fireEtaMonths: null,
    currencyMismatchCount: currencyMismatch,
    computedAt: DateTime.utc(2026, 5, 20),
  );
}

void main() {
  group('runStressTests', () {
    test('returns nothing when the plan is unconfigured', () {
      final state = computeFireState(
        plan: FirePlan.unset(baseCurrency: 'CNY'),
        netWorth: Money.zero('CNY'),
        investableAssets: Money.zero('CNY'),
        liquidAssets: Money.zero('CNY'),
        trailingAnnualSpend: null,
        fireEtaMonths: null,
        currencyMismatchCount: 0,
        computedAt: DateTime.utc(2026, 5, 20),
      );
      expect(runStressTests(state), isEmpty);
    });

    test('returns one result per scenario in stable order', () {
      final results = runStressTests(_state());
      expect(
        results.map((r) => r.scenario).toList(),
        [
          FireStressScenario.marketDrawdown,
          FireStressScenario.expenseSurge,
          FireStressScenario.oneOffShock,
          FireStressScenario.fxShock,
          FireStressScenario.cashDepletion,
        ],
      );
    });

    test('market drawdown -35% scales investable assets', () {
      final r = runStressTests(_state()).first;
      // 2_000_000 × 0.65 = 1_300_000.
      expect(r.investableAssetsAfter.amount, Decimal.parse('1300000'));
      // Net worth dropped by the same delta.
      expect(r.netWorthAfter.amount, Decimal.parse('1300000'));
      // WR after = 48_000 / 1_300_000 ≈ 0.0369; still ≤ SWR (4%) — safe.
      expect(r.withdrawalRateAfter, closeTo(48000 / 1300000, 1e-9));
      expect(r.verdict, FireStressVerdict.safe);
    });

    test('expense +20% pushes verdict for a marginal plan', () {
      // Investable 1_500_000, spend 48_000 → WR 3.2% (safe).
      // After +20% → spend 57_600 → WR 3.84% (still safe).
      // Annual 60_000 to make it bite: WR before = 4% boundary.
      final state = _state(
        investable: '1500000',
        annualSpend: '60000',
        netWorth: '1500000',
      );
      final stress = runStressTests(state);
      final surge = stress.firstWhere(
        (r) => r.scenario == FireStressScenario.expenseSurge,
      );
      // 60_000 × 1.2 = 72_000.
      expect(surge.annualSpendAfter.amount, Decimal.parse('72000'));
      expect(surge.withdrawalRateAfter, closeTo(72000 / 1500000, 1e-9));
      // 4.8% > SWR (4%), but ≤ 1.5×SWR (6%) → cautious.
      expect(surge.verdict, FireStressVerdict.cautious);
    });

    test('one-off shock removes the configured outlay from liquid + invest',
        () {
      final state = _state(oneOff: 20000);
      final shock = runStressTests(state).firstWhere(
        (r) => r.scenario == FireStressScenario.oneOffShock,
      );
      expect(shock.netWorthAfter.amount, Decimal.parse('1980000'));
      expect(shock.investableAssetsAfter.amount, Decimal.parse('1980000'));
      // Liquid 48_000 - 20_000 = 28_000 → cash months = 28000 / 4000 = 7.
      expect(shock.cashBucketMonthsAfter, closeTo(7.0, 1e-9));
      expect(shock.verdict, FireStressVerdict.cautious);
    });

    test('fx shock with currency mismatches nudges safe → cautious', () {
      final state = _state(currencyMismatch: 2, fx: 0.05);
      final fx = runStressTests(state).firstWhere(
        (r) => r.scenario == FireStressScenario.fxShock,
      );
      expect(fx.verdict, FireStressVerdict.cautious);
      expect(fx.note, contains('fx_gaps_present'));
    });

    test('cash depletion subtracts horizon × monthly from liquid', () {
      final state = _state(liquid: '120000', cashMonths: 6);
      // Horizon: targetCashBucketMonths = 6, monthly = 4_000 → depletes
      // by 24_000 → liquid after 96_000 → cash months 24.
      final depl = runStressTests(state).firstWhere(
        (r) => r.scenario == FireStressScenario.cashDepletion,
      );
      expect(depl.cashBucketMonthsAfter, closeTo(24.0, 1e-9));
      expect(depl.verdict, FireStressVerdict.safe);
    });

    test('zero-asset plan goes to danger across the board', () {
      final state = _state(
        investable: '0',
        liquid: '0',
        netWorth: '0',
      );
      final results = runStressTests(state);
      for (final r in results) {
        expect(r.verdict, FireStressVerdict.danger);
      }
    });

    test('overrides bypass plan risk settings', () {
      final base = _state(drawdown: 0.10);
      final stress = runStressTests(
        base,
        marketDrawdownOverride: const FireStressParams(drawdownPct: 0.5),
      );
      final drawdown = stress.first;
      expect(drawdown.params.drawdownPct, 0.5);
      // 2_000_000 × 0.5 = 1_000_000.
      expect(
        drawdown.investableAssetsAfter.amount,
        Decimal.parse('1000000'),
      );
    });

    test('toJson omits infinity withdrawal rate, includes all params', () {
      final state = _state(investable: '0', annualSpend: '60000');
      final r = runStressTests(state).firstWhere(
        (r) => r.scenario == FireStressScenario.marketDrawdown,
      );
      final json = r.toJson();
      expect(json['scenario'], 'market_drawdown');
      expect(json['withdrawal_rate_after'], isNull);
      expect((json['params'] as Map)['drawdown_pct'], 0.35);
    });
  });
}
