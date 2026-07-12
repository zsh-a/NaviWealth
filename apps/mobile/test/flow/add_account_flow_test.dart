// Flow / Task test: "Add account" — Task #2 in docs/development/testing-strategy.md.
//
// This uses the real AccountRepository against an in-memory Drift database
// while keeping unrelated market/asset providers deterministic. The task
// proves the user can discover the account creation path from Wealth, save
// an account, and see it return to the live account list.

import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/data/repositories/account_repository.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';

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
        await closeApp(tester);
      },
      tags: 'flow',
    );

    testWidgets(
      'user edits an existing account from the Wealth accounts surface',
      (tester) async {
        final accountRepo = AccountRepository(
          db: data.db,
          outbox: data.outbox,
          stamper: data.stamper,
        );
        final account = await accountRepo.create(
          type: AccountCategory.bank,
          name: 'Flow Checking',
          currency: 'CNY',
        );

        await bootApp(tester, liveData: data);

        final shell = AppShell(tester)..expectMounted();
        await shell.openTab('Wealth');

        final wealth = WealthPage(tester);
        await wealth.openAccounts();

        final accounts = AccountsPageObject(tester);
        await accounts.openAccount('Flow Checking');
        await accounts.editOpenAccount();

        final form = AccountFormObject(tester);
        form.expectEditMode('Flow Checking');
        await form.enterName('Flow Checking Renamed');
        await form.save();

        accounts.expectAccountVisible('Flow Checking Renamed');

        final saved = await accountRepo.findById(account.id);
        expect(saved?.name, 'Flow Checking Renamed');
        await closeApp(tester);
      },
      tags: 'flow',
    );
  });
}
