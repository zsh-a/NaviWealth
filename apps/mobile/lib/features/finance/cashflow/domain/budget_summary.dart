/// Read-model joining a calendar month's budget plans with the realised
/// spend for that month (`docs/roadmap-next.md` §3.2). Pure domain — no
/// I/O — so the FIRE engine and the Plan-tab dashboard can both consume
/// the same shape without re-querying.
library;

import 'package:decimal/decimal.dart';

import 'package:naviwealth/features/finance/domain/fx/money.dart';

class BudgetCategoryPlan {
  const BudgetCategoryPlan({
    required this.categoryId,
    required this.periodMonth,
    required this.amount,
    required this.currency,
    this.deletedAt,
  });

  final String categoryId;
  final String periodMonth;
  final Decimal amount;
  final String currency;
  final DateTime? deletedAt;
}

/// One category's budget posture: how much was set, how much was spent,
/// and whether the user is on track / at risk / over.
class CategoryBudgetStatus {
  CategoryBudgetStatus({
    required this.categoryId,
    required this.budgeted,
    required this.spent,
  }) : _budgetedAmount = budgeted.amount,
       _spentAmount = spent.amount;

  /// Stable category id — typically a system expense account id, but the
  /// reader treats it as an opaque key. Whatever the caller used when
  /// writing the budget is what's compared against the spend map.
  final String categoryId;

  /// Budget set by the user. Both monies must share a currency — the
  /// constructor doesn't *enforce* it because the spend map can carry a
  /// converted total; equality of currencies is the caller's invariant.
  final Money budgeted;

  /// Realised spend in the same currency. `Money.zero(currency)` when
  /// the user has set a budget but hasn't spent anything yet.
  final Money spent;

  final Decimal _budgetedAmount;
  final Decimal _spentAmount;

  /// `spent / budgeted`. Returns 0 when `budgeted` is zero (defensive —
  /// the repo enforces non-negative, but UI may render mid-write).
  double get progressFraction {
    if (_budgetedAmount <= Decimal.zero) return 0.0;
    return (_spentAmount.toDouble() / _budgetedAmount.toDouble()).clamp(
      0.0,
      99.0,
    );
  }

  /// `budgeted - spent`. Negative when the user is over budget — the
  /// sign carries the over/under direction; consumers can branch on
  /// [Money.isNegative] without re-computing.
  Money get remaining => budgeted - spent;

  bool get isOverBudget => spent > budgeted;

  bool get hasRemainingHeadroom => spent <= budgeted;
}

/// Roll-up across every category for a given month. The header lets the
/// dashboard render "你花了 70%" without iterating the children.
class MonthlyBudgetSummary {
  const MonthlyBudgetSummary({
    required this.periodMonth,
    required this.currency,
    required this.totalBudgeted,
    required this.totalSpent,
    required this.categories,
  });

  /// `YYYY-MM` of the underlying budgets.
  final String periodMonth;

  /// Reporting currency every line is presented in.
  final String currency;

  final Money totalBudgeted;
  final Money totalSpent;
  final List<CategoryBudgetStatus> categories;

  double get progressFraction {
    if (totalBudgeted.amount <= Decimal.zero) return 0.0;
    return (totalSpent.amount.toDouble() / totalBudgeted.amount.toDouble())
        .clamp(0.0, 99.0);
  }

  Money get totalRemaining => totalBudgeted - totalSpent;

  bool get isOverBudget => totalSpent > totalBudgeted;

  /// Categories sorted by how strained they are — overspends first
  /// (largest first), then under-budget rows in original order. Useful
  /// for the dashboard insight strip which surfaces the worst case.
  List<CategoryBudgetStatus> get rankedByStrain {
    final over = categories.where((c) => c.isOverBudget).toList()
      ..sort((a, b) => b.spent.amount.compareTo(a.spent.amount));
    final under = categories.where((c) => !c.isOverBudget).toList();
    return [...over, ...under];
  }
}

/// Join a month's [budgets] with realised [spendByCategoryId] (typically
/// pulled from the expense report's `CategoryBreakdown`).
///
/// Currency handling: every status uses `targetCurrency` — the caller is
/// expected to have FX-converted the spend map into the report currency
/// before handing it in. Budgets stored in another currency are dropped
/// rather than silently sign-flipped (the dropped count is in the result's
/// `mismatchedCount` for the UI to surface).
({MonthlyBudgetSummary summary, int mismatchedCount})
buildMonthlyBudgetSummary({
  required String periodMonth,
  required Iterable<BudgetCategoryPlan> budgets,
  required Map<String, Money> spendByCategoryId,
  required String targetCurrency,
}) {
  final upper = targetCurrency.toUpperCase();
  final statuses = <CategoryBudgetStatus>[];
  var totalBudgetedAmount = Decimal.zero;
  var totalSpentAmount = Decimal.zero;
  var mismatched = 0;

  for (final row in budgets) {
    if (row.deletedAt != null) continue;
    if (row.periodMonth != periodMonth) continue;
    if (row.currency.toUpperCase() != upper) {
      mismatched += 1;
      continue;
    }
    final budgeted = Money(row.amount, upper);
    final spend = spendByCategoryId[row.categoryId];
    final spent = spend == null
        ? Money.zero(upper)
        : (spend.currency.toUpperCase() == upper ? spend : Money.zero(upper));
    statuses.add(
      CategoryBudgetStatus(
        categoryId: row.categoryId,
        budgeted: budgeted,
        spent: spent,
      ),
    );
    totalBudgetedAmount += budgeted.amount;
    totalSpentAmount += spent.amount;
  }

  return (
    summary: MonthlyBudgetSummary(
      periodMonth: periodMonth,
      currency: upper,
      totalBudgeted: Money(totalBudgetedAmount, upper),
      totalSpent: Money(totalSpentAmount, upper),
      categories: statuses,
    ),
    mismatchedCount: mismatched,
  );
}
