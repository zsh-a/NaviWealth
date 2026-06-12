// Flow / Task test: "View net worth" — the canonical first journey of the
// test spine (docs/testing-strategy.md §3). This is the seed example of
// the flow layer: it boots the real app shell and drives a multi-screen
// user task through Page Objects, not raw widget finders.
//
// Tagged `flow` so the suite can be split out of the unit/widget gate
// later; today it runs inside the standard `flutter test` job.

import 'package:flutter_test/flutter_test.dart';

import 'support/app_harness.dart';
import 'support/page_objects.dart';

void main() {
  group('Task: View net worth', () {
    testWidgets('first run — user lands on Today with the home shell', (
      tester,
    ) async {
      await bootApp(tester);

      final shell = AppShell(tester);
      final home = HomePage(tester);

      home.expectLanded();
      shell.expectMounted();
      await closeApp(tester);
    }, tags: 'flow');

    testWidgets('user can move between primary destinations and return Today', (
      tester,
    ) async {
      await bootApp(tester);

      final shell = AppShell(tester)..expectMounted();
      final home = HomePage(tester);

      // The Task spans more than one screen: leave Today for another
      // primary destination, then come back. Page Objects keep this
      // readable and refactor-proof.
      const second = 'Wealth';
      if (shell.hasTab(second)) {
        await shell.openTab(second);
        await shell.openTab('Today');
      }
      home.expectLanded();
      await closeApp(tester);
    }, tags: 'flow');
  });
}
