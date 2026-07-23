// Flow / Task test: "Adjust budget".
//
// Boots the real app shell, opens Budget from Plan, edits an existing
// category cap, and verifies the row was updated in the live in-memory DB.

import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/auth/current_user.dart';
import 'package:naviwealth/features/finance/data/repositories/budget_repository.dart';
import 'package:naviwealth/features/finance/expense/data/expense_category_repository.dart';

import 'support/app_harness.dart';
import 'support/page_objects.dart';

void main() {
  group('Task: Adjust budget', () {
    late FlowDataHarness data;

    setUp(() async {
      data = await FlowDataHarness.create();
    });

    tearDown(() async {
      await data.dispose();
    });

    testWidgets('user edits a monthly category budget from Plan', (
      tester,
    ) async {
      final repo = BudgetRepository(
        db: data.db,
        outbox: data.outbox,
        stamper: data.stamper,
        ownerUserId: kLocalOnlyUserId,
      );
      final categoryId = ExpenseCategoryRepository.systemCategoryId(
        kLocalOnlyUserId,
        'dining',
      );
      final budget = await repo.create(
        categoryId: categoryId,
        periodMonth: _currentMonthKey(),
        amount: Decimal.parse('1500'),
        currency: 'CNY',
        note: 'Initial dining cap',
      );

      await bootApp(tester, liveData: data);

      final shell = AppShell(tester)..expectMounted();
      await shell.openTab('Plan');

      final plan = PlanPageObject(tester);
      await plan.openBudget();

      final page = BudgetPageObject(tester);
      page.expectBudgetVisible('Dining');
      await page.editBudget(
        categoryId: categoryId,
        amount: '1800',
        note: 'Flow dining cap',
      );
      page.expectNoteVisible('Flow dining cap');

      final saved = await repo.findForCategoryMonth(
        categoryId: budget.categoryId,
        periodMonth: budget.periodMonth,
      );
      expect(saved, isNotNull);
      expect(saved!.amount, Decimal.parse('1800'));
      expect(saved.note, 'Flow dining cap');

      await closeApp(tester);
    }, tags: 'flow');
  });
}

String _currentMonthKey() {
  final now = DateTime.now().toUtc();
  return '${now.year}-${now.month.toString().padLeft(2, '0')}';
}
