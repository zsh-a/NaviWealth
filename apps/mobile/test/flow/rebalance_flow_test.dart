// Flow / Task test: "Rebalance" — Task #8 in docs/testing-strategy.md.
//
// This boots the real app shell, discovers Rebalance from the Plan hub, and
// lands on the rebalance execution surface. The first-run empty state is
// intentional: it pins the route and the prerequisite guidance before any
// allocation data exists.

import 'package:flutter_test/flutter_test.dart';

import 'support/app_harness.dart';
import 'support/page_objects.dart';

void main() {
  group('Task: Rebalance', () {
    testWidgets('user opens the rebalance surface from Plan', (tester) async {
      await bootApp(tester);

      final shell = AppShell(tester)..expectMounted();
      await shell.openTab('Plan');

      final plan = PlanPageObject(tester);
      await plan.openRebalance();

      RebalancePageObject(tester).expectEmptyPlan();
      await closeApp(tester);
    }, tags: 'flow');
  });
}
