import 'package:flutter/foundation.dart';

import '../../../data/domain/expense.dart';
import '../../../domain/values/money.dart';
import 'expense_report_range.dart';

/// One month bucket in the trend bar chart.
///
/// [year] / [month] are calendar (UTC) coordinates so the renderer can
/// label "2026-04" without a local-time round-trip; [total] is the
/// base-currency sum of every non-skipped expense whose [Expense.tradeDate]
/// fell inside the bucket.
@immutable
class MonthlyExpenseBucket {
  const MonthlyExpenseBucket({
    required this.year,
    required this.month,
    required this.total,
  });

  final int year;
  final int month;
  final Money total;

  String get key => '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}';
}

/// Total spend rolled up into a top-level category for the pie chart.
///
/// [items] is every individual expense that fell into this category /
/// sub-category tree, kept around so the drill-down sheet can list them
/// without re-querying. Sorted descending by [total] inside the report.
@immutable
class CategoryBreakdown {
  const CategoryBreakdown({
    required this.categoryId,
    required this.total,
    required this.items,
    this.subCategories = const <CategoryBreakdown>[],
  });

  /// Top-level category id. Sub-categories are flattened up to their
  /// nearest top-level ancestor; the original sub-category appears under
  /// [subCategories] for the drill-down level-2 pie.
  final String categoryId;
  final Money total;
  final List<Expense> items;

  /// Per-sub-category roll-up *within* this top-level. Empty for top-level
  /// categories that have no children. Sorted descending by total; each
  /// entry's [items] is the sub-category's individual rows only.
  final List<CategoryBreakdown> subCategories;
}

/// Aggregated view backing the report page.
///
/// All monetary fields are already converted to [baseCurrency]; expenses
/// the converter could not service (no FX rate available on / before the
/// trade date) are counted in [skippedFxCount] instead of being silently
/// dropped without any signal.
@immutable
class ExpenseReport {
  const ExpenseReport({
    required this.range,
    required this.baseCurrency,
    required this.total,
    required this.monthlyBuckets,
    required this.byCategory,
    required this.skippedFxCount,
  });

  final ExpenseReportRange range;
  final String baseCurrency;

  /// Sum of every included expense, in [baseCurrency].
  final Money total;

  /// 12-month trend buckets — always [ExpenseReportRange.monthSpan] long
  /// (gaps filled with zero) so the bar chart never has missing bars.
  final List<MonthlyExpenseBucket> monthlyBuckets;

  /// Top-level category breakdown, sorted descending by total. Empty when
  /// no expenses fell inside the window.
  final List<CategoryBreakdown> byCategory;

  /// Number of expenses excluded from totals because their currency could
  /// not be converted to [baseCurrency] (no FX rate <= the trade date).
  /// Surface this in the UI rather than silently zeroing them out.
  final int skippedFxCount;

  bool get isEmpty => byCategory.isEmpty;
}
