import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/domain/values/money.dart';
import 'package:naviwealth/features/cashflow/domain/budget_signal.dart';
import 'package:naviwealth/features/cashflow/domain/budget_summary.dart';

CategoryBudgetStatus _cat(String id, String budget, String spent) =>
    CategoryBudgetStatus(
      categoryId: id,
      budgeted: Money.parse(budget, 'CNY'),
      spent: Money.parse(spent, 'CNY'),
    );

MonthlyBudgetSummary _summary(List<CategoryBudgetStatus> cats) {
  var budgeted = Decimal.zero;
  var spent = Decimal.zero;
  for (final c in cats) {
    budgeted += c.budgeted.amount;
    spent += c.spent.amount;
  }
  return MonthlyBudgetSummary(
    periodMonth: '2026-05',
    currency: 'CNY',
    totalBudgeted: Money(budgeted, 'CNY'),
    totalSpent: Money(spent, 'CNY'),
    categories: cats,
  );
}

void main() {
  group('budgetSignalFor', () {
    test('empty summary → noData', () {
      expect(budgetSignalFor(_summary(const [])), BudgetSignal.noData);
    });

    test('zero spend across all categories → noData', () {
      final s = _summary([_cat('food', '1000', '0')]);
      expect(budgetSignalFor(s), BudgetSignal.noData);
    });

    test('spend under 80% of total → comfortable', () {
      final s = _summary([
        _cat('food', '1000', '500'),
        _cat('rent', '5000', '4000'),
      ]);
      // 4500 / 6000 = 75% → comfortable.
      expect(budgetSignalFor(s), BudgetSignal.comfortable);
    });

    test('spend between 80% and 100% → strained', () {
      final s = _summary([
        _cat('food', '1000', '900'),
        _cat('rent', '5000', '4400'),
      ]);
      // 5300 / 6000 ≈ 88%.
      expect(budgetSignalFor(s), BudgetSignal.strained);
    });

    test('any over-budget category bumps comfortable → strained', () {
      final s = _summary([
        _cat('food', '1000', '1200'), // 120% — over
        _cat('rent', '5000', '500'), // way under
      ]);
      // Total: 1700 / 6000 ≈ 28% → would be comfortable, but food is
      // over → strained.
      expect(budgetSignalFor(s), BudgetSignal.strained);
    });

    test('total spent > total budgeted → overBudget', () {
      final s = _summary([
        _cat('food', '1000', '1500'),
        _cat('rent', '5000', '5000'),
      ]);
      expect(budgetSignalFor(s), BudgetSignal.overBudget);
    });

    test('boundary: exactly 80% → strained (inclusive at the lower edge)', () {
      final s = _summary([_cat('food', '1000', '800')]);
      expect(budgetSignalFor(s), BudgetSignal.strained);
    });

    test('wire form is snake_case', () {
      expect(BudgetSignal.noData.wire, 'no_data');
      expect(BudgetSignal.comfortable.wire, 'comfortable');
      expect(BudgetSignal.strained.wire, 'strained');
      expect(BudgetSignal.overBudget.wire, 'over_budget');
    });
  });
}
