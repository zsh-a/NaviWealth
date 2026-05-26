import 'package:decimal/decimal.dart';

import 'package:naviwealth/features/finance/data/domain/expense.dart';
import '../../../domain/services/currency_converter.dart';
import '../../../domain/values/money.dart';
import 'expense_report.dart';
import 'expense_report_range.dart';

/// Pure roll-up from raw [Expense] rows to the report model.
///
/// Holds no state; the aggregator is constructed per snapshot so the
/// provider layer can pass in a fresh [CurrencyConverter] / base currency
/// without invalidating cached buckets. Performance: a single linear pass
/// over expenses.
class ExpenseReportAggregator {
  ExpenseReportAggregator({
    required this.converter,
    required this.baseCurrency,
  });

  final CurrencyConverter converter;
  final String baseCurrency;

  /// Aggregate [expenses] over [range].
  ExpenseReport aggregate({
    required Iterable<Expense> expenses,
    required ExpenseReportRange range,
  }) {
    final monthlyTotals = _seedMonthlyBuckets(range);

    final accountTotals = <String, Decimal>{};
    final accountItems = <String, List<Expense>>{};

    var grandTotal = Decimal.zero;
    var skippedFxCount = 0;

    for (final expense in expenses) {
      if (expense.tradeDate.isBefore(range.from)) continue;
      if (!expense.tradeDate.isBefore(range.to)) continue;

      final native = Money(expense.amount, expense.currency);
      Money converted;
      try {
        converted = converter.convert(
          native,
          baseCurrency,
          on: expense.tradeDate,
        );
      } on FxRateNotFoundError {
        skippedFxCount++;
        continue;
      }

      final delta = converted.amount;
      grandTotal += delta;

      final localTradeDate = expense.tradeDate.toUtc();
      final monthKey =
          '${localTradeDate.year.toString().padLeft(4, '0')}-'
          '${localTradeDate.month.toString().padLeft(2, '0')}';
      monthlyTotals[monthKey] =
          (monthlyTotals[monthKey] ?? Decimal.zero) + delta;

      final accountId = expense.expenseAccountId;
      accountTotals[accountId] =
          (accountTotals[accountId] ?? Decimal.zero) + delta;
      accountItems.putIfAbsent(accountId, () => <Expense>[]).add(expense);
    }

    // Materialise the trend buckets in chronological order.
    final monthBuckets = monthlyTotals.entries.map((entry) {
      final parts = entry.key.split('-');
      return MonthlyExpenseBucket(
        year: int.parse(parts[0]),
        month: int.parse(parts[1]),
        total: Money(entry.value, baseCurrency),
      );
    }).toList()..sort((a, b) => a.key.compareTo(b.key));

    final breakdowns = accountTotals.entries.map((entry) {
      return CategoryBreakdown(
        expenseAccountId: entry.key,
        total: Money(entry.value, baseCurrency),
        items: accountItems[entry.key] ?? const <Expense>[],
      );
    }).toList()..sort((a, b) => b.total.amount.compareTo(a.total.amount));

    return ExpenseReport(
      range: range,
      baseCurrency: baseCurrency,
      total: Money(grandTotal, baseCurrency),
      monthlyBuckets: monthBuckets,
      byCategory: breakdowns,
      skippedFxCount: skippedFxCount,
    );
  }

  /// Pre-fill every month inside [range] with zero so the bar chart shows
  /// an empty bar instead of a gap when a month had no spending.
  Map<String, Decimal> _seedMonthlyBuckets(ExpenseReportRange range) {
    final out = <String, Decimal>{};
    var year = range.from.year;
    var month = range.from.month;
    final lastIncluded = range.to.subtract(const Duration(days: 1));
    final endYear = lastIncluded.year;
    final endMonth = lastIncluded.month;
    while (year < endYear || (year == endYear && month <= endMonth)) {
      final key =
          '${year.toString().padLeft(4, '0')}-'
          '${month.toString().padLeft(2, '0')}';
      out[key] = Decimal.zero;
      month++;
      if (month > 12) {
        month = 1;
        year++;
      }
    }
    return out;
  }
}
