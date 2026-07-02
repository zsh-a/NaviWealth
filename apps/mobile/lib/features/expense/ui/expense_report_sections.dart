import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/features/finance/composition/finance_route_paths.dart';
import 'package:naviwealth/features/finance/data/domain/account.dart';
import 'package:naviwealth/features/finance/data/domain/expense.dart';

import '../../../core/format/formatters.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../finance/shared/account_l10n.dart';
import '../domain/expense_report.dart';
import 'expense_category_visuals.dart';

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

class _Pie extends StatelessWidget {
  const _Pie({required this.report, required this.categoryById});

  final ExpenseReport report;
  final Map<String, Account> categoryById;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final slices = <Slice>[
      for (var i = 0; i < report.byCategory.length; i++)
        Slice(
          label: _categoryLabel(
            l10n,
            categoryById[report.byCategory[i].expenseAccountId],
            l10n.expenseReportUncategorized,
          ),
          value: report.byCategory[i].total.amount.toDouble(),
          colorOverride:
              categoryById[report.byCategory[i].expenseAccountId]
                  ?.expenseAccentColor(context, ordinal: i) ??
              ChartPalette.of(context).accentAt(i),
          meta: report.byCategory[i],
        ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxSize = constraints.maxWidth < Breakpoints.mobile
            ? 208.0
            : 224.0;
        final size = constraints.maxWidth.clamp(168.0, maxSize).toDouble();
        return Align(
          alignment: Alignment.center,
          child: SizedBox.square(
            dimension: size,
            child: NwPieChart(
              slices: slices,
              hole: 0.66,
              minLabelPercent: 7,
              drillDown: SliceDrillDown((slice) {
                final breakdown = slice.meta;
                if (breakdown is! CategoryBreakdown) return;
                showAppFormSheet<void>(
                  context: context,
                  builder: (ctx) => _CategoryDrillDown(
                    breakdown: breakdown,
                    categoryById: categoryById,
                    baseCurrency: report.baseCurrency,
                  ),
                );
              }),
              semanticLabel: l10n.expenseReportCategoryShare,
            ),
          ),
        );
      },
    );
  }
}

class _PieLegend extends StatelessWidget {
  const _PieLegend({required this.report, required this.categoryById});

  final ExpenseReport report;
  final Map<String, Account> categoryById;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final total = report.total.amount.toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < report.byCategory.length; i++)
          _LegendRow(
            color:
                categoryById[report.byCategory[i].expenseAccountId]
                    ?.expenseAccentColor(context, ordinal: i) ??
                ChartPalette.of(context).accentAt(i),
            label: _categoryLabel(
              l10n,
              categoryById[report.byCategory[i].expenseAccountId],
              l10n.expenseReportUncategorized,
            ),
            valueInBase: report.byCategory[i].total.amount.toDouble(),
            currencyCode: report.baseCurrency,
            percent: total == 0
                ? 0
                : report.byCategory[i].total.amount.toDouble() / total,
            onTap: () => showAppFormSheet<void>(
              context: context,
              builder: (ctx) => _CategoryDrillDown(
                breakdown: report.byCategory[i],
                categoryById: categoryById,
                baseCurrency: report.baseCurrency,
              ),
            ),
          ),
        if (report.byCategory.isEmpty)
          Text(l10n.expenseReportNoExpenses, style: context.captionStyle),
      ],
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({
    required this.color,
    required this.label,
    required this.valueInBase,
    required this.currencyCode,
    required this.percent,
    required this.onTap,
  });

  final Color color;
  final String label;
  final double valueInBase;
  final String currencyCode;
  final double percent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.s6,
          horizontal: AppSpacing.s4,
        ),
        child: Row(
          children: [
            Container(
              width: AppSpacing.s12,
              height: AppSpacing.s12,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(AppRadius.xs),
              ),
            ),
            const SizedBox(width: AppSpacing.s8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: context.theme.typography.body.sm,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${(percent * 100).toStringAsFixed(1)}%',
                    style: context.captionStyle,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.s8),
            MoneyText(
              amount: valueInBase,
              currencyCode: currencyCode,
              compact: true,
            ),
            const SizedBox(width: AppSpacing.s4),
            Icon(
              FLucideIcons.chevronRight,
              size: AppIconSizes.sm,
              color: context.theme.colors.mutedForeground,
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.breakdown,
    required this.categoryById,
    required this.baseCurrency,
  });

  final CategoryBreakdown breakdown;
  final Map<String, Account> categoryById;
  final String baseCurrency;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final category = categoryById[breakdown.expenseAccountId];
    final accent =
        category?.expenseAccentColor(context) ?? context.theme.colors.primary;
    return FTappable(
      onPress: () => showAppFormSheet<void>(
        context: context,
        builder: (ctx) => _CategoryDrillDown(
          breakdown: breakdown,
          categoryById: categoryById,
          baseCurrency: baseCurrency,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s12,
          vertical: AppSpacing.s10,
        ),
        child: Row(
          children: [
            SizedBox(
              width: AppSpacing.s32,
              height: AppSpacing.s32,
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Icon(
                  category?.iconData ?? FLucideIcons.banknote,
                  size: AppIconSizes.md,
                  color: accent.withValues(alpha: AppOpacity.prominent),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _categoryLabel(
                      l10n,
                      category,
                      l10n.expenseReportUncategorized,
                    ),
                    style: context.labelStyle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpacing.s2),
                  Text(
                    l10n.expenseReportItemCount(breakdown.items.length),
                    style: context.captionStyle,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.s12),
            MoneyText(
              amount: breakdown.total.amount.toDouble(),
              currencyCode: baseCurrency,
              compact: true,
              style: context.strongLabelStyle,
            ),
          ],
        ),
      ),
    );
  }
}

String _categoryLabel(
  AppLocalizations l10n,
  Account? account,
  String fallback,
) {
  return account == null ? fallback : localizedAccountName(l10n, account);
}

class _CategoryDrillDown extends StatelessWidget {
  const _CategoryDrillDown({
    required this.breakdown,
    required this.categoryById,
    required this.baseCurrency,
  });

  final CategoryBreakdown breakdown;
  final Map<String, Account> categoryById;
  final String baseCurrency;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final formatter = AppFormatters(locale: Localizations.localeOf(context));
    final category = categoryById[breakdown.expenseAccountId];
    final entries = [...breakdown.items]
      ..sort((a, b) => b.tradeDate.compareTo(a.tradeDate));

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (ctx, scrollController) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.s16,
            AppSpacing.s8,
            AppSpacing.s16,
            AppSpacing.s24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    category?.iconData ?? FLucideIcons.banknote,
                    color: context.theme.colors.primary,
                  ),
                  const SizedBox(width: AppSpacing.s8),
                  Expanded(
                    child: Text(
                      _categoryLabel(
                        l10n,
                        category,
                        l10n.expenseReportUncategorized,
                      ),
                      style: context.rowTitleStyle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s8),
                  MoneyText(
                    amount: breakdown.total.amount.toDouble(),
                    currencyCode: baseCurrency,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.s4),
              Text(
                l10n.expenseReportItemCount(entries.length),
                style: context.captionStyle,
              ),
              const SizedBox(height: AppSpacing.s12),
              const FDivider(),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: entries.length,
                  itemBuilder: (ctx, i) {
                    final exp = entries[i];
                    return _ExpenseLine(
                      expense: exp,
                      formatter: formatter,
                      onTap: () {
                        Navigator.of(ctx).pop();
                        context.push(FinanceRoutes.expense(exp.id));
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ExpenseLine extends StatelessWidget {
  const _ExpenseLine({
    required this.expense,
    required this.formatter,
    this.onTap,
  });

  final Expense expense;
  final AppFormatters formatter;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return FTappable(
      onPress: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s2,
          vertical: AppSpacing.s10,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    expense.note ?? formatter.date(expense.tradeDate),
                    style: context.labelStyle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpacing.s2),
                  Text(
                    formatter.date(expense.tradeDate),
                    style: context.captionStyle,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.s12),
            Text(
              formatter.currency(expense.amount, code: expense.currency),
              style: context.strongLabelStyle.copyWith(
                fontFeatures: TypographyTokens.tabularFigures,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
