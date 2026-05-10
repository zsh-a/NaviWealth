import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../../../core/format/formatters.dart';
import '../../../data/domain/account.dart';
import '../../../data/domain/expense.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
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
    final theme = Theme.of(context);
    return FCard.raw(
      child: Padding(
        padding: Spacing.cardHero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.expenseReportCategoryShare,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: Spacing.s12),
            if (report.byCategory.isEmpty)
              LayoutBuilder(
                builder: (context, c) => AspectRatio(
                  aspectRatio: chartAspectFor(c.maxWidth),
                  child: const EmptyChartPlaceholder(icon: Icons.donut_large),
                ),
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
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: pie),
                        const SizedBox(width: Spacing.s24),
                        Expanded(child: legend),
                      ],
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      pie,
                      const SizedBox(height: Spacing.s12),
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
    final theme = Theme.of(context);
    final palette = ChartPalette.of(context);
    final data = [
      for (final bucket in report.monthlyBuckets)
        CategoryDatum(
          label: l10n.expenseReportMonthLabel(bucket.month),
          value: bucket.total.amount.toDouble(),
          colorOverride: palette.accentAt(0),
        ),
    ];
    return FCard.raw(
      child: Padding(
        padding: Spacing.cardHero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.expenseReportMonthlyTrend,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: Spacing.s12),
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
                  height: 220,
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
    final theme = Theme.of(context);
    if (report.byCategory.isEmpty) {
      return const SizedBox.shrink();
    }
    return FCard.raw(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.s4,
          vertical: Spacing.s8,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Spacing.s12,
                Spacing.s8,
                Spacing.s12,
                Spacing.s4,
              ),
              child: Text(
                l10n.expenseReportCategoryDetail,
                style: theme.textTheme.titleMedium,
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
    final palette = ChartPalette.of(context);
    final slices = <Slice>[
      for (var i = 0; i < report.byCategory.length; i++)
        Slice(
          label:
              categoryById[report.byCategory[i].expenseAccountId]?.name ??
              l10n.expenseReportUncategorized,
          value: report.byCategory[i].total.amount.toDouble(),
          colorOverride: palette.accentAt(i),
          meta: report.byCategory[i],
        ),
    ];
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 240),
      child: NwPieChart(
        slices: slices,
        drillDown: SliceDrillDown((slice) {
          final breakdown = slice.meta;
          if (breakdown is! CategoryBreakdown) return;
          showModalBottomSheet<void>(
            context: context,
            showDragHandle: true,
            isScrollControlled: true,
            builder: (ctx) => _CategoryDrillDown(
              breakdown: breakdown,
              categoryById: categoryById,
              baseCurrency: report.baseCurrency,
            ),
          );
        }),
        semanticLabel: l10n.expenseReportCategoryShare,
      ),
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
    final theme = Theme.of(context);
    final palette = ChartPalette.of(context);
    final total = report.total.amount.toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < report.byCategory.length; i++)
          _LegendRow(
            color: palette.accentAt(i),
            label:
                categoryById[report.byCategory[i].expenseAccountId]?.name ??
                l10n.expenseReportUncategorized,
            valueInBase: report.byCategory[i].total.amount.toDouble(),
            currencyCode: report.baseCurrency,
            percent: total == 0
                ? 0
                : report.byCategory[i].total.amount.toDouble() / total,
            onTap: () => showModalBottomSheet<void>(
              context: context,
              showDragHandle: true,
              isScrollControlled: true,
              builder: (ctx) => _CategoryDrillDown(
                breakdown: report.byCategory[i],
                categoryById: categoryById,
                baseCurrency: report.baseCurrency,
              ),
            ),
          ),
        if (report.byCategory.isEmpty)
          Text(
            l10n.expenseReportNoExpenses,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
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
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: Spacing.s6,
          horizontal: Spacing.s4,
        ),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: Spacing.s8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: theme.textTheme.bodyMedium),
                  Text(
                    '${(percent * 100).toStringAsFixed(1)}%',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            MoneyText(
              amount: valueInBase,
              currencyCode: currencyCode,
              compact: true,
            ),
            const SizedBox(width: Spacing.s4),
            Icon(
              Icons.chevron_right,
              size: 16,
              color: theme.colorScheme.onSurfaceVariant,
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
    final theme = Theme.of(context);
    final category = categoryById[breakdown.expenseAccountId];
    final accent = category?.accentColor ?? theme.colorScheme.primary;
    return FTile(
      title: Text(category?.name ?? l10n.expenseReportUncategorized),
      prefix: CircleAvatar(
        backgroundColor: accent.withValues(alpha: 0.15),
        child: Icon(category?.iconData ?? Icons.payment, color: accent),
      ),
      subtitle: Text(l10n.expenseReportItemCount(breakdown.items.length)),
      suffix: MoneyText(
        amount: breakdown.total.amount.toDouble(),
        currencyCode: baseCurrency,
        compact: true,
      ),
      onPress: () => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (ctx) => _CategoryDrillDown(
          breakdown: breakdown,
          categoryById: categoryById,
          baseCurrency: baseCurrency,
        ),
      ),
    );
  }
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
    final theme = Theme.of(context);
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
            Spacing.s16,
            Spacing.s8,
            Spacing.s16,
            Spacing.s24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    category?.iconData ?? Icons.payment,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: Spacing.s8),
                  Expanded(
                    child: Text(
                      category?.name ?? l10n.expenseReportUncategorized,
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  MoneyText(
                    amount: breakdown.total.amount.toDouble(),
                    currencyCode: baseCurrency,
                  ),
                ],
              ),
              const SizedBox(height: Spacing.s4),
              Text(
                l10n.expenseReportItemCount(entries.length),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: Spacing.s12),
              const FDivider(),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: entries.length,
                  itemBuilder: (ctx, i) {
                    final exp = entries[i];
                    return _ExpenseLine(expense: exp, formatter: formatter);
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
  const _ExpenseLine({required this.expense, required this.formatter});

  final Expense expense;
  final AppFormatters formatter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FTile(
      title: Text(expense.note ?? formatter.date(expense.tradeDate)),
      subtitle: Text(formatter.date(expense.tradeDate)),
      suffix: Text(
        formatter.currency(expense.amount, code: expense.currency),
        style: theme.textTheme.bodyMedium?.copyWith(
          fontFeatures: TypographyTokens.tabularFigures,
        ),
      ),
    );
  }
}
