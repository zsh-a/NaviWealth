import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/life_events/data/financial_decision_providers.dart';
import 'package:naviwealth/features/finance/life_events/domain/life_event_scenario.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('saved decision survives controller recreation', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final controller = FinancialDecisionController(preferences);
    final assumptions = LifeEventAssumptions(
      upfrontCost: Decimal.zero,
      monthlyIncomeDelta: Decimal.zero,
      monthlyOutflowDelta: Decimal.zero,
      durationMonths: 1,
    );
    final outcome = LifeEventOutcome(
      liquidAfter90Days: Decimal.zero,
      liquidAfter12Months: Decimal.zero,
      monthlySurplus: Decimal.zero,
      coverageMonths: null,
      estimatedFireDelayMonths: null,
    );

    await controller.save(
      template: LifeEventTemplate.largePurchase,
      assumptions: assumptions,
      outcome: outcome,
      now: DateTime.utc(2026, 7, 19),
    );
    final restored = FinancialDecisionController(preferences);

    expect(restored.state, hasLength(1));
    expect(restored.state.single.template, LifeEventTemplate.largePurchase);
    expect(restored.state.single.reviewDate, DateTime.utc(2026, 10, 17));
  });
}
