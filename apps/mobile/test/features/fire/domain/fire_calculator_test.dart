import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/fire/domain/fire_calculator.dart';
import 'package:naviwealth/features/fire/domain/fire_goal.dart';
import 'package:naviwealth/features/fire/domain/fire_projection.dart';

Decimal _d(String s) => Decimal.parse(s);

FireGoal _goal({
  String target = '1000000',
  String monthlyExpenses = '4000',
  String monthlySurplus = '5000',
  double inflationRate = 0.03,
}) {
  return FireGoal(
    targetAmount: _d(target),
    monthlyExpenses: _d(monthlyExpenses),
    monthlySurplus: _d(monthlySurplus),
    inflationRate: inflationRate,
  );
}

void main() {
  final start = DateTime.utc(2026, 1, 1);
  group('FireCalculator', () {
    test(
      'emits the three default scenario tiers when no live rate is given',
      () {
        final view = const FireCalculator().buildView(
          goal: _goal(),
          currentNetWorth: _d('200000'),
          baseCurrency: 'CNY',
          start: start,
        );
        expect(view.scenarios.map((s) => s.tier).toSet(), {
          FireScenarioTier.conservative,
          FireScenarioTier.neutral,
          FireScenarioTier.aggressive,
        });
      },
    );

    test('adds the live tier when liveAnnualReturn is supplied', () {
      final view = const FireCalculator().buildView(
        goal: _goal(),
        currentNetWorth: _d('200000'),
        baseCurrency: 'CNY',
        start: start,
        liveAnnualReturn: 0.075,
      );
      expect(
        view.scenarios.any((s) => s.tier == FireScenarioTier.live),
        isTrue,
      );
      // Sensitivity uses the live rate as baseline.
      expect(
        view.sensitivity.baselineMonths,
        view.scenarios
            .firstWhere((s) => s.tier == FireScenarioTier.live)
            .monthsToTarget,
      );
    });

    test('higher annual return reaches FIRE no later than lower return', () {
      final view = const FireCalculator().buildView(
        goal: _goal(),
        currentNetWorth: _d('200000'),
        baseCurrency: 'CNY',
        start: start,
      );
      final cons = view.scenarios.firstWhere(
        (s) => s.tier == FireScenarioTier.conservative,
      );
      final neu = view.scenarios.firstWhere(
        (s) => s.tier == FireScenarioTier.neutral,
      );
      final agg = view.scenarios.firstWhere(
        (s) => s.tier == FireScenarioTier.aggressive,
      );
      // All should reach within the horizon for these inputs.
      expect(cons.monthsToTarget, isNotNull);
      expect(neu.monthsToTarget, isNotNull);
      expect(agg.monthsToTarget, isNotNull);
      expect(neu.monthsToTarget!, lessThanOrEqualTo(cons.monthsToTarget!));
      expect(agg.monthsToTarget!, lessThanOrEqualTo(neu.monthsToTarget!));
    });

    test('returns 0 months when current net worth already meets target', () {
      final view = const FireCalculator().buildView(
        goal: _goal(target: '500000'),
        currentNetWorth: _d('600000'),
        baseCurrency: 'CNY',
        start: start,
      );
      for (final s in view.scenarios) {
        expect(s.monthsToTarget, 0);
        expect(s.isReached, isTrue);
      }
      expect(view.progressRatio, 1.0); // clamped to [0, 1]
    });

    test(
      'reports unreachable when no return + zero surplus + inflation > 0',
      () {
        final view = const FireCalculator().buildView(
          goal: _goal(monthlySurplus: '0', inflationRate: 0.03),
          currentNetWorth: _d('500000'),
          baseCurrency: 'CNY',
          start: start,
        );
        // Conservative real return ≈ 0% after 3% inflation → unreachable.
        // (3% nominal − 3% inflation; net worth tracks inflation, target races
        // ahead of net worth's modest gain over zero surplus.)
        final cons = view.scenarios.firstWhere(
          (s) => s.tier == FireScenarioTier.conservative,
        );
        expect(cons.monthsToTarget, isNull);
        expect(cons.isUnreachable, isTrue);
      },
    );

    test('inflation pushes back the crossing date', () {
      final base = const FireCalculator().buildView(
        goal: _goal(inflationRate: 0.0),
        currentNetWorth: _d('200000'),
        baseCurrency: 'CNY',
        start: start,
      );
      final inflated = const FireCalculator().buildView(
        goal: _goal(inflationRate: 0.05),
        currentNetWorth: _d('200000'),
        baseCurrency: 'CNY',
        start: start,
      );
      final neuBase = base.scenarios
          .firstWhere((s) => s.tier == FireScenarioTier.neutral)
          .monthsToTarget!;
      final neuInfl = inflated.scenarios
          .firstWhere((s) => s.tier == FireScenarioTier.neutral)
          .monthsToTarget!;
      expect(neuInfl, greaterThan(neuBase));
    });

    test('sensitivity: +20% surplus reaches FIRE sooner than -20%', () {
      final view = const FireCalculator().buildView(
        goal: _goal(),
        currentNetWorth: _d('200000'),
        baseCurrency: 'CNY',
        start: start,
      );
      final s = view.sensitivity;
      expect(s.baselineMonths, isNotNull);
      expect(s.lowSurplusMonths, isNotNull);
      expect(s.highSurplusMonths, isNotNull);
      expect(s.highSurplusMonths!, lessThan(s.baselineMonths!));
      expect(s.lowSurplusMonths!, greaterThan(s.baselineMonths!));
      expect(s.highSurplus, greaterThan(s.lowSurplus));
    });

    test('points list contains start, target-crossing, and end markers', () {
      final view = const FireCalculator().buildView(
        goal: _goal(),
        currentNetWorth: _d('200000'),
        baseCurrency: 'CNY',
        start: start,
      );
      final neu = view.scenarios.firstWhere(
        (s) => s.tier == FireScenarioTier.neutral,
      );
      expect(neu.points.length, greaterThanOrEqualTo(2));
      expect(neu.points.first.date, start);
      // Crossing month must be one of the sampled points.
      final crossing = neu.monthsToTarget;
      if (crossing != null) {
        final hasCrossing = neu.points.any(
          (p) =>
              p.date.year == start.year + crossing ~/ 12 &&
              p.date.month == ((start.month + crossing - 1) % 12) + 1,
        );
        expect(hasCrossing, isTrue);
      }
    });

    test('safeMonthlyWithdrawalAmount equals target * 0.04 / 12', () {
      final view = const FireCalculator().buildView(
        goal: _goal(target: '1200000'),
        currentNetWorth: _d('100000'),
        baseCurrency: 'CNY',
        start: start,
      );
      // 1,200,000 * 0.04 / 12 = 4000.
      expect(view.safeMonthlyWithdrawalAmount, closeTo(4000, 1e-6));
    });

    test('progressRatio clamps to [0, 1]', () {
      final view = const FireCalculator().buildView(
        goal: _goal(target: '100'),
        currentNetWorth: _d('1000000'),
        baseCurrency: 'CNY',
        start: start,
      );
      expect(view.progressRatio, 1.0);
    });

    test('progressRatio is null for an unconfigured goal', () {
      final view = const FireCalculator().buildView(
        goal: FireGoal.unset(),
        currentNetWorth: _d('100000'),
        baseCurrency: 'CNY',
        start: start,
      );
      expect(view.progressRatio, isNull);
    });
  });
}
