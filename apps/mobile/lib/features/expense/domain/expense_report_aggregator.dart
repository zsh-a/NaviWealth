import 'package:decimal/decimal.dart';

import '../../../data/domain/expense.dart';
import '../../../data/domain/expense_category.dart';
import '../../../domain/services/currency_converter.dart';
import '../../../domain/values/money.dart';
import 'expense_report.dart';
import 'expense_report_range.dart';

/// FIR-70 — pure roll-up from raw [Expense] rows to the report model.
///
/// Holds no state; the aggregator is constructed per snapshot so the
/// provider layer can pass in a fresh [CurrencyConverter] / base currency
/// without invalidating cached buckets. Performance: a single linear pass
/// over expenses; categories are looked up via a map built once up-front.
class ExpenseReportAggregator {
  ExpenseReportAggregator({
    required this.converter,
    required this.baseCurrency,
  });

  final CurrencyConverter converter;
  final String baseCurrency;

  /// Aggregate [expenses] over [range]. [categories] is the full active +
  /// archived list (the report still needs to render archived categories
  /// that own historical expenses). `parent_id`-linked rows are flattened
  /// into their top-level ancestor for the pie chart; the original
  /// sub-category lives under [CategoryBreakdown.subCategories].
  ExpenseReport aggregate({
    required Iterable<Expense> expenses,
    required Iterable<ExpenseCategory> categories,
    required ExpenseReportRange range,
  }) {
    final categoryById = {for (final c in categories) c.id: c};

    // Top-level resolution: walk up the parent chain (max one hop given
    // the two-level taxonomy) until we find a row without a parent or
    // we've broken a cycle / hit a missing parent.
    String topLevelOf(String id) {
      var cursor = categoryById[id];
      var hops = 0;
      while (cursor != null && cursor.parentId != null && hops < 4) {
        final parent = categoryById[cursor.parentId];
        if (parent == null) break;
        cursor = parent;
        hops++;
      }
      return cursor?.id ?? id;
    }

    final monthlyTotals = _seedMonthlyBuckets(range);

    // Top-level totals + per-top-level sub-category accumulation.
    final topTotals = <String, Decimal>{};
    final topItems = <String, List<Expense>>{};
    final subTotals = <String, Map<String, Decimal>>{};
    final subItems = <String, Map<String, List<Expense>>>{};

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
      final monthKey = '${localTradeDate.year.toString().padLeft(4, '0')}-'
          '${localTradeDate.month.toString().padLeft(2, '0')}';
      monthlyTotals[monthKey] = (monthlyTotals[monthKey] ?? Decimal.zero) + delta;

      final top = topLevelOf(expense.categoryId);
      topTotals[top] = (topTotals[top] ?? Decimal.zero) + delta;
      topItems.putIfAbsent(top, () => <Expense>[]).add(expense);

      // Track sub-category totals only when the expense is filed under a
      // child of [top] — top-level expenses aren't sub-totaled against
      // themselves (that would double-count in the drill-down pie).
      if (expense.categoryId != top) {
        subTotals
            .putIfAbsent(top, () => <String, Decimal>{})
            .update(
              expense.categoryId,
              (v) => v + delta,
              ifAbsent: () => delta,
            );
        subItems
            .putIfAbsent(top, () => <String, List<Expense>>{})
            .putIfAbsent(expense.categoryId, () => <Expense>[])
            .add(expense);
      }
    }

    // Materialise the trend buckets in chronological order.
    final monthBuckets = monthlyTotals.entries.map((entry) {
      final parts = entry.key.split('-');
      return MonthlyExpenseBucket(
        year: int.parse(parts[0]),
        month: int.parse(parts[1]),
        total: Money(entry.value, baseCurrency),
      );
    }).toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    final breakdowns = topTotals.entries.map((entry) {
      final subs = (subTotals[entry.key] ?? const <String, Decimal>{})
          .entries
          .map(
            (sub) => CategoryBreakdown(
              categoryId: sub.key,
              total: Money(sub.value, baseCurrency),
              items: subItems[entry.key]?[sub.key] ?? const <Expense>[],
            ),
          )
          .toList()
        ..sort((a, b) => b.total.amount.compareTo(a.total.amount));

      return CategoryBreakdown(
        categoryId: entry.key,
        total: Money(entry.value, baseCurrency),
        items: topItems[entry.key] ?? const <Expense>[],
        subCategories: subs,
      );
    }).toList()
      ..sort((a, b) => b.total.amount.compareTo(a.total.amount));

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
      final key = '${year.toString().padLeft(4, '0')}-'
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
