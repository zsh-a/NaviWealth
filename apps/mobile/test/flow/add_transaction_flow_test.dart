// Flow / Task test: "Add transaction" — Task #3 in docs/testing-strategy.md.
//
// This boots the real app shell, discovers the Activity quick-add menu, and
// enters the trade-entry surface. The accounting write path is covered by
// lower-level trade-entry and repository tests; this flow pins the user-facing
// route and form contract.

import 'package:flutter_test/flutter_test.dart';

import 'support/app_harness.dart';
import 'support/page_objects.dart';

void main() {
  group('Task: Add transaction', () {
    testWidgets('user opens the trade-entry form from Activity', (
      tester,
    ) async {
      await bootApp(tester);

      final shell = AppShell(tester)..expectMounted();
      await shell.openTab('Activity');

      final activity = ActivityPageObject(tester);
      await activity.openTradeEntry();

      TradeEntryPageObject(tester).expectCreateMode();
      await closeApp(tester);
    }, tags: 'flow');
  });
}
