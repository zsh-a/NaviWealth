// Flow / Task test: "Generate FIRE report" — Task #10 in
// docs/testing-strategy.md.
//
// This boots the real app shell, discovers FIRE from the Plan hub, and lands
// on the FIRE report surface. The first-run state is intentional: it proves
// the report route gives a clear setup CTA before any FIRE assumptions exist.

import 'package:flutter_test/flutter_test.dart';

import 'support/app_harness.dart';
import 'support/page_objects.dart';

void main() {
  group('Task: Generate FIRE report', () {
    testWidgets('user opens the FIRE report surface from Plan', (tester) async {
      await bootApp(tester);

      final shell = AppShell(tester)..expectMounted();
      await shell.openTab('Plan');

      final plan = PlanPageObject(tester);
      await plan.openFireReport();

      FireReportPageObject(tester).expectUnconfiguredReport();
      await closeApp(tester);
    }, tags: 'flow');
  });
}
