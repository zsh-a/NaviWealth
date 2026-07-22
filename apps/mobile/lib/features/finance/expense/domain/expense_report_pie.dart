import 'package:naviwealth/features/finance/domain/fx/money.dart';

import 'expense_report.dart';

/// Synthetic pie-slice id for the rolled-up long-tail bucket.
const String kExpenseReportPieOtherId = '__expense_report_other__';

/// Max named slices on the expense report pie before the rest roll into
/// "Other". Keeps the donut readable with the categorical palette.
const int kExpenseReportPieMaxSlices = 8;

/// Collapses a descending category breakdown into top-[maxSlices] named
/// slices plus an optional "Other" roll-up for the pie chart.
///
/// [byCategory] must already be sorted descending by total (as produced by
/// [ExpenseReportAggregator]). When the list is already short enough the
/// input is returned unchanged.
List<CategoryBreakdown> collapseExpenseCategoriesForPie(
  List<CategoryBreakdown> byCategory, {
  int maxSlices = kExpenseReportPieMaxSlices,
}) {
  assert(maxSlices >= 1, 'maxSlices must be at least 1');
  if (byCategory.length <= maxSlices) {
    return List<CategoryBreakdown>.of(byCategory);
  }

  final headCount = maxSlices - 1;
  final head = byCategory.take(headCount).toList(growable: false);
  final tail = byCategory.skip(headCount).toList(growable: false);

  var otherAmount = tail.first.total.amount;
  for (var i = 1; i < tail.length; i++) {
    otherAmount += tail[i].total.amount;
  }
  final mergedCount = tail.fold<int>(0, (sum, bucket) => sum + bucket.count);

  final other = CategoryBreakdown(
    expenseAccountId: kExpenseReportPieOtherId,
    total: Money(otherAmount, tail.first.total.currency),
    count: mergedCount,
  );

  return [...head, other];
}

/// Pre-collapse tail rows for the synthetic [kExpenseReportPieOtherId]
/// bucket, or `null` when [breakdown] is not the Other roll-up.
///
/// Matches [collapseExpenseCategoriesForPie] so the Activity drill-down
/// opens the same set of underlying categories.
List<CategoryBreakdown>? expenseReportOtherSource({
  required List<CategoryBreakdown> byCategory,
  required CategoryBreakdown breakdown,
  int maxSlices = kExpenseReportPieMaxSlices,
}) {
  if (breakdown.expenseAccountId != kExpenseReportPieOtherId) return null;
  if (byCategory.length <= maxSlices) return null;
  return byCategory.skip(maxSlices - 1).toList(growable: false);
}
