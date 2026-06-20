// Flow / Task test: "Add transaction" — Task #3 in docs/testing-strategy.md.
//
// This boots the real app shell, discovers the Activity quick-add menu, and
// records an expense through the real in-memory journal repository. The task
// proves the user-facing "log a fact" path writes a visible ledger row.

import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/data/domain/enums.dart';
import 'package:naviwealth/features/finance/data/repositories/account_repository.dart';

import 'support/app_harness.dart';
import 'support/page_objects.dart';

void main() {
  group('Task: Add transaction', () {
    late FlowDataHarness data;

    setUp(() async {
      data = await FlowDataHarness.create();
    });

    tearDown(() async {
      await data.dispose();
    });

    testWidgets('user records an expense from Activity and sees it listed', (
      tester,
    ) async {
      final accountRepo = AccountRepository(
        db: data.db,
        outbox: data.outbox,
        stamper: data.stamper,
      );
      await accountRepo.seedSystemAccounts();
      final cash = await accountRepo.create(
        type: AccountCategory.bank,
        name: 'Flow Checking',
        currency: 'CNY',
      );
      const categoryId = 'system-account:u-test:expense:dining';

      await bootApp(
        tester,
        liveData: data,
        initialPrefs: {
          'naviwealth.forms.expense.account': cash.id,
          'naviwealth.forms.expense.category': categoryId,
          'naviwealth.forms.expense.currency': 'CNY',
        },
      );

      final shell = AppShell(tester)..expectMounted();
      await shell.openTab('Activity');

      final activity = ActivityPageObject(tester);
      await activity.openExpenseEntry();

      final form = ExpenseFormObject(tester);
      form.expectCreateMode();
      await form.enterAmount('38.50');
      await form.enterNote('Flow coffee');
      await form.save();

      await activity.openExpenseList();
      ExpenseListPageObject(tester).expectExpenseVisible('Flow coffee');
      await closeApp(tester);
    }, tags: 'flow');
  });
}
