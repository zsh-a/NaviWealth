// Flow / Task test: "Plan options income" — Task #9 in
// docs/development/testing-strategy.md.
//
// This boots the real app shell, discovers Income strategy from the Plan hub,
// and lands on the Income Planner setup surface. The first-run state is
// intentional: options income must start with explicit user risk disclosure
// and strategy preferences before any scan or journal workflow.

import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/options_income/data/providers.dart';

import 'support/app_harness.dart';
import 'support/page_objects.dart';

void main() {
  group('Task: Plan options income', () {
    testWidgets('user opens Income Planner from Plan', (tester) async {
      await bootApp(
        tester,
        extraOverrides: [
          optionsStrategyProfileProvider.overrideWith(
            (ref) => Stream.value(null),
          ),
        ],
      );

      final shell = AppShell(tester)..expectMounted();
      await shell.openTab('Plan');

      final plan = PlanPageObject(tester);
      await plan.openIncomeStrategy();

      IncomePlannerPageObject(tester).expectStartState();
      await closeApp(tester);
    }, tags: 'flow');
  });
}
