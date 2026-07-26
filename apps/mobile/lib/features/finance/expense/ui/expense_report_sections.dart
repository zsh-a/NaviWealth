import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/composition/finance_route_paths.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../../../../core/format/formatters.dart';
import '../domain/expense_category.dart';
import '../domain/expense_report.dart';
import '../domain/expense_report_pie.dart';
import 'expense_category_l10n.dart';
import 'expense_category_visuals.dart';

part 'expense_report_helpers.dart';
part 'expense_report_pie.dart';

void _openSpendingBreakdown(
  BuildContext context, {
  required ExpenseReport report,
  required CategoryBreakdown breakdown,
  required Map<String, ExpenseCategory> categoryById,
}) {
  final source = expenseReportOtherSource(
    byCategory: report.byCategory,
    breakdown: breakdown,
  );
  final categoryIds = source == null
      ? <String>{breakdown.categoryId}
      : source.map((item) => item.categoryId).toSet();
  final accountIds = categoryIds
      .map((id) => categoryById[id]?.ledgerAccountId)
      .whereType<String>()
      .toSet();
  context.go(
    FinanceRoutes.activityFeed(
      from: report.range.from,
      to: report.range.to,
      kinds: const <String>['expense'],
      accountIds: accountIds,
    ),
  );
}

class ExpenseCategoryPieCard extends StatelessWidget {
  const ExpenseCategoryPieCard({
    super.key,
    required this.report,
    required this.categoryById,
  });

  final ExpenseReport report;
  final Map<String, ExpenseCategory> categoryById;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SoftCard(
      level: SoftCardLevel.raised,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.expenseReportCategoryShare,
              style: context.theme.typography.body.md,
            ),
            const SizedBox(height: AppSpacing.s12),
            if (report.byCategory.isEmpty)
              const SizedBox(
                height: AppChartHeights.standard,
                child: EmptyChartPlaceholder(icon: FLucideIcons.chartPie),
              )
            else
              LayoutBuilder(
                builder: (context, c) {
                  final l10n = AppLocalizations.of(context);
                  final slices = buildExpenseReportPieSlices(
                    context,
                    report: report,
                    categoryById: categoryById,
                    labelOf: (breakdown) =>
                        _breakdownLabel(l10n, breakdown, categoryById),
                  );
                  final isWide = c.maxWidth >= Breakpoints.mobile;
                  final pie = _Pie(
                    report: report,
                    categoryById: categoryById,
                    slices: slices,
                  );
                  final legend = _PieLegend(
                    report: report,
                    categoryById: categoryById,
                    slices: slices,
                  );
                  if (isWide) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: AppControlWidths.chartSidePanel,
                          child: pie,
                        ),
                        const SizedBox(width: AppSpacing.s20),
                        Expanded(child: legend),
                      ],
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      pie,
                      const SizedBox(height: AppSpacing.s12),
                      legend,
                    ],
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class ExpenseTrendCard extends StatelessWidget {
  const ExpenseTrendCard({super.key, required this.report});

  final ExpenseReport report;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = ChartPalette.of(context);
    final data = [
      for (final bucket in report.monthlyBuckets)
        CategoryDatum(
          label: l10n.expenseReportMonthLabel(bucket.month),
          value: bucket.total.amount.toDouble(),
          colorOverride: palette.accentAt(0),
        ),
    ];
    return SoftCard(
      level: SoftCardLevel.raised,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.expenseReportMonthlyTrend,
              style: context.theme.typography.body.md,
            ),
            const SizedBox(height: AppSpacing.s12),
            LayoutBuilder(
              builder: (context, c) {
                final aspect = chartAspectFor(c.maxWidth);
                if (data.isEmpty) {
                  return AspectRatio(
                    aspectRatio: aspect,
                    child: const EmptyChartPlaceholder(),
                  );
                }
                return SizedBox(
                  height: AppChartHeights.full,
                  child: NwBarChart(
                    series: [
                      CategorySeries(
                        name: l10n.expenseReportSeriesExpenses,
                        data: data,
                      ),
                    ],
                    yAxis: ValueAxis.currency(
                      currencyCode: report.baseCurrency,
                      maxLabels: 4,
                    ),
                    aspectRatio: aspect,
                    semanticLabel: l10n.expenseReportMonthlyTrendSemantic,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
