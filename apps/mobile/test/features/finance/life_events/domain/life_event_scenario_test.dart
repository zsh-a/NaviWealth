import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/life_events/domain/life_event_scenario.dart';

void main() {
  const engine = LifeEventScenarioEngine();
  final baseline = LifeEventBaseline(
    liquidBalance: Decimal.fromInt(100000),
    monthlyIncome: Decimal.fromInt(20000),
    monthlyOutflow: Decimal.fromInt(10000),
    currency: 'CNY',
    fireMonthsToTarget: 120,
  );

  test('career break applies its delta only for the selected duration', () {
    final assumptions = engine.preset(LifeEventTemplate.careerBreak, baseline);
    final outcome = engine.simulate(baseline, assumptions);

    expect(outcome.liquidAfter90Days, Decimal.fromInt(70000));
    expect(outcome.liquidAfter12Months, Decimal.fromInt(100000));
    expect(outcome.monthlySurplus, Decimal.fromInt(-10000));
    expect(outcome.estimatedFireDelayMonths, 12);
  });

  test('observed snapshot is independent from prior assumptions', () {
    final observed = engine.observe(baseline);

    expect(observed.liquidAfter90Days, Decimal.fromInt(100000));
    expect(observed.monthlySurplus, Decimal.fromInt(10000));
    expect(observed.coverageMonths, 10);
  });
}
