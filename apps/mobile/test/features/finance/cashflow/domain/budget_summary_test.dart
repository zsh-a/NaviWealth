import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/cashflow/domain/budget_summary.dart';
import 'package:naviwealth/features/finance/domain/fx/money.dart';

void main() {
  BudgetCategoryPlan seedBudget({
    required String categoryId,
    String periodMonth = '2026-05',
    required String amount,
    String currency = 'CNY',
    DateTime? deletedAt,
  }) => BudgetCategoryPlan(
    categoryId: categoryId,
    periodMonth: periodMonth,
    amount: Decimal.parse(amount),
    currency: currency,
    deletedAt: deletedAt,
  );

  group('buildMonthlyBudgetSummary', () {
    test('joins matching budget + spend by categoryId', () {
      final food = seedBudget(categoryId: 'cat-food', amount: '1500');
      final rent = seedBudget(categoryId: 'cat-rent', amount: '5000');

      final result = buildMonthlyBudgetSummary(
        periodMonth: '2026-05',
        budgets: [food, rent],
        spendByCategoryId: {
          'cat-food': Money.parse('1200', 'CNY'),
          'cat-rent': Money.parse('5000', 'CNY'),
        },
        targetCurrency: 'CNY',
      );

      expect(result.mismatchedCount, 0);
      expect(result.summary.categories, hasLength(2));
      expect(result.summary.totalBudgeted, Money.parse('6500', 'CNY'));
      expect(result.summary.totalSpent, Money.parse('6200', 'CNY'));
      expect(result.summary.progressFraction, closeTo(0.954, 0.01));
    });

    test('category with no spend defaults to zero, retains its budget', () {
      final food = seedBudget(categoryId: 'cat-food', amount: '1500');

      final result = buildMonthlyBudgetSummary(
        periodMonth: '2026-05',
        budgets: [food],
        spendByCategoryId: const {},
        targetCurrency: 'CNY',
      );

      final s = result.summary.categories.single;
      expect(s.spent, Money.zero('CNY'));
      expect(s.remaining, Money.parse('1500', 'CNY'));
      expect(s.progressFraction, 0.0);
      expect(s.isOverBudget, isFalse);
    });

    test('over-budget category is correctly flagged', () {
      final food = seedBudget(categoryId: 'cat-food', amount: '1000');

      final result = buildMonthlyBudgetSummary(
        periodMonth: '2026-05',
        budgets: [food],
        spendByCategoryId: {'cat-food': Money.parse('1300', 'CNY')},
        targetCurrency: 'CNY',
      );
      final s = result.summary.categories.single;
      expect(s.isOverBudget, isTrue);
      expect(s.remaining.isNegative, isTrue);
      expect(s.remaining.amount, Decimal.parse('-300'));
    });

    test('drops budgets in a different currency, counts them', () {
      final cny = seedBudget(categoryId: 'cat-food', amount: '1000');
      final usd = seedBudget(
        categoryId: 'cat-travel',
        amount: '500',
        currency: 'USD',
      );

      final result = buildMonthlyBudgetSummary(
        periodMonth: '2026-05',
        budgets: [cny, usd],
        spendByCategoryId: const {},
        targetCurrency: 'CNY',
      );

      expect(result.summary.categories, hasLength(1));
      expect(result.summary.categories.single.categoryId, 'cat-food');
      expect(result.mismatchedCount, 1);
    });

    test('filters out budgets from other months and tombstones', () {
      final may = seedBudget(
        categoryId: 'cat-food',
        periodMonth: '2026-05',
        amount: '1000',
      );
      final april = seedBudget(
        categoryId: 'cat-food',
        periodMonth: '2026-04',
        amount: '900',
        deletedAt: DateTime.utc(2026, 5, 2),
      );
      final june = seedBudget(
        categoryId: 'cat-food',
        periodMonth: '2026-06',
        amount: '1100',
      );

      final result = buildMonthlyBudgetSummary(
        periodMonth: '2026-05',
        budgets: [may, april, june],
        spendByCategoryId: const {},
        targetCurrency: 'CNY',
      );
      expect(result.summary.categories.map((c) => c.categoryId), ['cat-food']);
      // April + June are filtered (deleted / wrong month). Only May
      // contributes to the total.
      expect(result.summary.totalBudgeted, Money.parse('1000', 'CNY'));
    });

    test('rankedByStrain surfaces over-budget categories first', () {
      final overBig = seedBudget(categoryId: 'cat-rent', amount: '5000');
      final overSmall = seedBudget(categoryId: 'cat-food', amount: '1000');
      final under = seedBudget(categoryId: 'cat-fun', amount: '500');

      final result = buildMonthlyBudgetSummary(
        periodMonth: '2026-05',
        budgets: [under, overSmall, overBig],
        spendByCategoryId: {
          'cat-rent': Money.parse('6000', 'CNY'),
          'cat-food': Money.parse('1100', 'CNY'),
          'cat-fun': Money.parse('200', 'CNY'),
        },
        targetCurrency: 'CNY',
      );
      final ranked = result.summary.rankedByStrain;
      // Over-budget rows, ordered by spent desc.
      expect(ranked[0].categoryId, 'cat-rent');
      expect(ranked[1].categoryId, 'cat-food');
      // Under-budget last.
      expect(ranked[2].categoryId, 'cat-fun');
    });

    test('total roll-up flags the whole month as over budget', () {
      final a = seedBudget(categoryId: 'cat-a', amount: '500');
      final b = seedBudget(categoryId: 'cat-b', amount: '500');

      final result = buildMonthlyBudgetSummary(
        periodMonth: '2026-05',
        budgets: [a, b],
        spendByCategoryId: {
          'cat-a': Money.parse('800', 'CNY'),
          'cat-b': Money.parse('400', 'CNY'),
        },
        targetCurrency: 'CNY',
      );
      // 800 + 400 = 1200 > 1000 budget.
      expect(result.summary.isOverBudget, isTrue);
      expect(result.summary.totalRemaining.amount, Decimal.parse('-200'));
    });
  });
}
