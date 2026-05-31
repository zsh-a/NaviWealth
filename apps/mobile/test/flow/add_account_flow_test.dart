// Flow / Task test: "Add account" — Task #2 in docs/testing-strategy.md.
//
// This uses the real AccountRepository against an in-memory Drift database
// while keeping unrelated market/asset providers deterministic. The task
// proves the user can discover the account creation path from Wealth, save
// an account, and see it return to the live account list.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/app_harness.dart';
import 'support/page_objects.dart';

void main() {
  group('Task: Add account', () {
    late FlowDataHarness data;

    setUp(() async {
      data = await FlowDataHarness.create();
    });

    tearDown(() async {
      await data.dispose();
    });

    testWidgets(
      'user creates a bank account from the Wealth accounts surface',
      (tester) async {
        await bootApp(tester, liveData: data);

        final shell = AppShell(tester)..expectMounted();
        await shell.openTab('Wealth');

        final wealth = WealthPage(tester);
        await wealth.openAccounts();

        final accounts = AccountsPageObject(tester);
        accounts.expectEmptyState();
        await accounts.startNewAccount();

        final form = AccountFormObject(tester);
        form.expectCreateMode();
        await form.enterName('Flow Checking');
        await form.save();

        accounts.expectAccountVisible('Flow Checking');
        shell.expectMounted();

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(Duration.zero);
      },
      tags: 'flow',
    );
  });
}
