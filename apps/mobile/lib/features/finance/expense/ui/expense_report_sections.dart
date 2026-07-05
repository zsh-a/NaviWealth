import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/core/format/formatters.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/composition/finance_route_paths.dart';
import 'package:naviwealth/features/finance/domain/models/account.dart';
import 'package:naviwealth/features/finance/domain/models/expense.dart';
import 'package:naviwealth/features/finance/shared/l10n/account_l10n.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../domain/expense_report.dart';
import 'expense_category_visuals.dart';

part 'expense_report_category_list.dart';
part 'expense_report_drill_down.dart';
part 'expense_report_helpers.dart';
part 'expense_report_pie.dart';

class ExpenseCategoryPieCard extends StatelessWidget {
  const ExpenseCategoryPieCard({
    super.key,
    required this.report,
    required this.categoryById,
  });

  final ExpenseReport report;
  final Map<String, Account> categoryById;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SoftCard(
      borderless: true,
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
                height: AppChartHeights.card,
                child: EmptyChartPlaceholder(icon: FLucideIcons.chartPie),
              )
            else
              LayoutBuilder(
                builder: (context, c) {
                  final isWide = c.maxWidth >= Breakpoints.mobile;
                  final pie = _Pie(report: report, categoryById: categoryById);
                  final legend = _PieLegend(
                    report: report,
                    categoryById: categoryById,
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
      borderless: true,
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

class ExpenseCategoryListCard extends StatelessWidget {
  const ExpenseCategoryListCard({
    super.key,
    required this.report,
    required this.categoryById,
  });

  final ExpenseReport report;
  final Map<String, Account> categoryById;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (report.byCategory.isEmpty) {
      return const SizedBox.shrink();
    }
    return SoftCard(
      borderless: true,
      tinted: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s4,
          vertical: AppSpacing.s8,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.s12,
                AppSpacing.s8,
                AppSpacing.s12,
                AppSpacing.s4,
              ),
              child: Text(
                l10n.expenseReportCategoryDetail,
                style: context.theme.typography.body.md,
              ),
            ),
            for (final breakdown in report.byCategory)
              _CategoryTile(
                breakdown: breakdown,
                categoryById: categoryById,
                baseCurrency: report.baseCurrency,
              ),
          ],
        ),
      ),
    );
  }
}
