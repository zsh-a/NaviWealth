// Flow / Task test: "Plan options income" — Task #9 in
// docs/development/testing-strategy.md.
//
// This boots the real app shell, discovers Income strategy from the Plan hub,
// and lands on the unified Income Strategy surface.

import 'package:flutter_test/flutter_test.dart';

import 'support/app_harness.dart';
import 'support/page_objects.dart';

void main() {
  group('Task: Plan options income', () {
    testWidgets('user opens Income Strategy from Plan', (tester) async {
      await bootApp(tester);

      final shell = AppShell(tester)..expectMounted();
      await shell.openTab('Plan');

      final plan = PlanPageObject(tester);
      await plan.openIncomeStrategy();

      expect(find.text('Income strategy'), findsWidgets);
      await closeApp(tester);
    }, tags: 'flow');
  });
}
