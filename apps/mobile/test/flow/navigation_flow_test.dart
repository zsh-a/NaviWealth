// Route smoke for FinanceOS tabs and the Plan entry points for Tasks 11/12.
//
// A route-smoke Task: every primary tab must resolve and keep the app
// shell mounted. Because the router's errorBuilder replaces the entire
// shell (bottom nav included) with the not-found page, asserting the nav
// is still mounted after each hop proves the route resolved — a 404 or a
// shell crash would fail it. Catches route/guard regressions during the
// responsive-layout refactors the strategy anticipates.

import 'package:flutter_test/flutter_test.dart';

import 'support/app_harness.dart';
import 'support/page_objects.dart';

void main() {
  group('Task: navigate primary destinations', () {
    // FinanceOS bottom-nav destinations
    // (lib/features/finance/composition/finance_domain_shell.dart).
    const primaryTabs = ['Today', 'Records', 'Wealth', 'Plan'];

    testWidgets('primary tabs and Plan tools resolve in one app session', (
      tester,
    ) async {
      await bootApp(tester);
      final shell = AppShell(tester)..expectMounted();

      for (final tab in primaryTabs) {
        await shell.openTab(tab);
        shell.expectMounted(); // not the 404 / error page
      }

      final plan = PlanPageObject(tester);
      await plan.openFireReport();
      FireReportPageObject(tester).expectUnconfiguredReport();
      await shell.goBack();
      shell.expectMounted();

      await plan.openIncomeStrategy();
      expect(find.text('Income strategy'), findsWidgets);
      await shell.goBack();
      shell.expectMounted();

      // End back on the landing surface.
      await shell.openTab('Today');
      HomePage(tester).expectLanded();
      await closeApp(tester);
    }, tags: 'flow');
  });
}
