import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format/formatters.dart';
import '../../../data/domain/account.dart';
import '../../../data/domain/enums.dart';
import '../../../data/domain/expense.dart';
import '../../../data/repositories/providers.dart';
import '../../../design_system/design_system.dart';
import '../data/expense_report_providers.dart';
import '../domain/expense_report.dart';
import '../domain/expense_report_range.dart';
import 'expense_category_visuals.dart';

/// FIR-70 — monthly spend report.
///
/// Mirrors the home dashboard: range chips at the top, then a category
/// pie + drill-down, then a 12-month trend bar chart, then a per-category
/// detail list. Everything is driven by [expenseReportProvider] so the
/// view has no internal state beyond the range chip + chart-vs-list tab.
class ExpenseReportPage extends ConsumerWidget {
  const ExpenseReportPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportAsync = ref.watch(expenseReportProvider);
    return Scaffold(
      appBar: const GlassAppBar(title: Text('支出报表')),
      body: reportAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('报表加载失败：$e')),
        data: (report) => _ReportBody(report: report),
      ),
    );
  }
}

class _ReportBody extends ConsumerWidget {
  const _ReportBody({required this.report});

  final ExpenseReport report;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountsAsync = ref.watch(accountsStreamProvider);
    final allAccounts = accountsAsync.value ?? const <Account>[];
    final expenseAccountById = {
      for (final a in allAccounts.where(
        (a) => a.category == AccountCategory.expense,
      ))
        a.id: a,
    };

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        Spacing.s12,
        Spacing.s8,
        Spacing.s12,
        Spacing.s24,
      ),
      children: [
        const _RangeChips(),
        const SizedBox(height: Spacing.s12),
        _SummaryCard(report: report),
        const SizedBox(height: Spacing.s12),
        _CategoryPieCard(report: report, categoryById: expenseAccountById),
        const SizedBox(height: Spacing.s12),
        _TrendCard(report: report),
        const SizedBox(height: Spacing.s12),
        _CategoryListCard(
          report: report,
          categoryById: expenseAccountById,
          accounts: allAccounts,
        ),
      ],
    );
  }
}

class _RangeChips extends ConsumerWidget {
  const _RangeChips();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(expenseReportRangePresetProvider);
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final preset in ExpenseReportRangePreset.values)
            Padding(
              padding: const EdgeInsets.only(right: Spacing.s8),
              child: AppChoiceChip(
                label: Text(_label(preset)),
                selected: preset == selected,
                onSelected: (_) => _select(context, ref, preset),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _select(
    BuildContext context,
    WidgetRef ref,
    ExpenseReportRangePreset preset,
  ) async {
    if (preset == ExpenseReportRangePreset.custom) {
      final now = DateTime.now();
      final initial = ref.read(expenseReportCustomRangeProvider) ??
          (
            from: DateTime(now.year, now.month - 2, 1),
            to: now,
          );
      final picked = await showDateRangePicker(
        context: context,
        initialDateRange: DateTimeRange(start: initial.from, end: initial.to),
        firstDate: DateTime(now.year - 5),
        lastDate: now,
      );
      if (picked == null) return;
      ref.read(expenseReportCustomRangeProvider.notifier).state =
          (from: picked.start, to: picked.end);
      ref.read(expenseReportRangePresetProvider.notifier).state = preset;
      return;
    }
    ref.read(expenseReportCustomRangeProvider.notifier).state = null;
    ref.read(expenseReportRangePresetProvider.notifier).state = preset;
  }

  String _label(ExpenseReportRangePreset preset) {
    switch (preset) {
      case ExpenseReportRangePreset.monthToDate:
        return '本月';
      case ExpenseReportRangePreset.m3:
        return '近 3 月';
      case ExpenseReportRangePreset.m6:
        return '近 6 月';
      case ExpenseReportRangePreset.m12:
        return '近 12 月';
      case ExpenseReportRangePreset.custom:
        return '自定义';
    }
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.report});

  final ExpenseReport report;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final formatter = AppFormatters(locale: Localizations.localeOf(context));
    final monthSpan = report.range.monthSpan;
    final divisor = Decimal.fromInt(monthSpan == 0 ? 1 : monthSpan);
    final avgDecimal = (report.total.amount / divisor).toDecimal(
      scaleOnInfinitePrecision: 2,
    );
    return Card(
      child: Padding(
        padding: Spacing.cardHero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('总支出', style: theme.textTheme.titleSmall),
            const SizedBox(height: Spacing.s4),
            Text(
              formatter.currency(report.total.amount, code: report.baseCurrency),
              style: theme.textTheme.headlineSmall?.copyWith(
                fontFeatures: TypographyTokens.tabularFigures,
              ),
            ),
            const SizedBox(height: Spacing.s8),
            Row(
              children: [
                Expanded(
                  child: _Metric(
                    label: '月均',
                    value: formatter.compactCurrency(
                      avgDecimal,
                      code: report.baseCurrency,
                    ),
                  ),
                ),
                Expanded(
                  child: _Metric(
                    label: '记账数',
                    value: report.byCategory
                        .fold<int>(0, (a, c) => a + c.items.length)
                        .toString(),
                  ),
                ),
                Expanded(
                  child: _Metric(
                    label: '类目数',
                    value: report.byCategory.length.toString(),
                  ),
                ),
              ],
            ),
            if (report.skippedFxCount > 0) ...[
              const SizedBox(height: Spacing.s8),
              Text(
                '${report.skippedFxCount} 笔支出因汇率缺失未计入合计。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: Spacing.s4),
            Text(
              '基础货币 ${report.baseCurrency} · 月均按 $monthSpan 个月折算',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontFeatures: TypographyTokens.tabularFigures,
          ),
        ),
      ],
    );
  }
}

class _CategoryPieCard extends StatelessWidget {
  const _CategoryPieCard({
    required this.report,
    required this.categoryById,
  });

  final ExpenseReport report;
  final Map<String, Account> categoryById;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: Spacing.cardHero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('类目占比', style: theme.textTheme.titleMedium),
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
                  final pie = _Pie(
                    report: report,
                    categoryById: categoryById,
                  );
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

class _Pie extends StatelessWidget {
  const _Pie({required this.report, required this.categoryById});

  final ExpenseReport report;
  final Map<String, Account> categoryById;

  @override
  Widget build(BuildContext context) {
    final palette = ChartPalette.of(context);
    final slices = <Slice>[
      for (var i = 0; i < report.byCategory.length; i++)
        Slice(
          label: categoryById[report.byCategory[i].expenseAccountId]?.name ?? '未分类',
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
          showGlassModalBottomSheet<void>(
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
        semanticLabel: '类目占比',
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
    final theme = Theme.of(context);
    final palette = ChartPalette.of(context);
    final total = report.total.amount.toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < report.byCategory.length; i++)
          _LegendRow(
            color: palette.accentAt(i),
            label: categoryById[report.byCategory[i].expenseAccountId]?.name ?? '未分类',
            valueInBase: report.byCategory[i].total.amount.toDouble(),
            currencyCode: report.baseCurrency,
            percent: total == 0
                ? 0
                : report.byCategory[i].total.amount.toDouble() / total,
            onTap: () => showGlassModalBottomSheet<void>(
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
            '本期没有支出记录。',
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

class _TrendCard extends StatelessWidget {
  const _TrendCard({required this.report});

  final ExpenseReport report;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = ChartPalette.of(context);
    final data = [
      for (final bucket in report.monthlyBuckets)
        CategoryDatum(
          label: '${bucket.month}月',
          value: bucket.total.amount.toDouble(),
          colorOverride: palette.accentAt(0),
        ),
    ];
    return Card(
      child: Padding(
        padding: Spacing.cardHero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('月度趋势', style: theme.textTheme.titleMedium),
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
                    series: [CategorySeries(name: '支出', data: data)],
                    yAxis: ValueAxis.currency(
                      currencyCode: report.baseCurrency,
                      maxLabels: 4,
                    ),
                    aspectRatio: aspect,
                    semanticLabel: '月度支出趋势',
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

class _CategoryListCard extends StatelessWidget {
  const _CategoryListCard({
    required this.report,
    required this.categoryById,
    required this.accounts,
  });

  final ExpenseReport report;
  final Map<String, Account> categoryById;
  final List<Account> accounts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (report.byCategory.isEmpty) {
      return const SizedBox.shrink();
    }
    return Card(
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
                '类目明细',
                style: theme.textTheme.titleMedium,
              ),
            ),
            for (final breakdown in report.byCategory)
              _CategoryTile(
                breakdown: breakdown,
                categoryById: categoryById,
                accounts: accounts,
                baseCurrency: report.baseCurrency,
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
    required this.accounts,
    required this.baseCurrency,
  });

  final CategoryBreakdown breakdown;
  final Map<String, Account> categoryById;
  final List<Account> accounts;
  final String baseCurrency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final category = categoryById[breakdown.expenseAccountId];
    final accent =
        category?.accentColor ?? theme.colorScheme.primary;
    return ListTile(
      onTap: () => showGlassModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (ctx) => _CategoryDrillDown(
          breakdown: breakdown,
          categoryById: categoryById,
          baseCurrency: baseCurrency,
        ),
      ),
      leading: CircleAvatar(
        backgroundColor: accent.withValues(alpha: 0.15),
        child: Icon(category?.iconData ?? Icons.payment, color: accent),
      ),
      title: Text(category?.name ?? '未分类'),
      subtitle: Text('${breakdown.items.length} 笔'),
      trailing: MoneyText(
        amount: breakdown.total.amount.toDouble(),
        currencyCode: baseCurrency,
        compact: true,
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
                      category?.name ?? '未分类',
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
                '${entries.length} 笔',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: Spacing.s12),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: entries.length,
                  itemBuilder: (ctx, i) {
                    final exp = entries[i];
                    return _ExpenseLine(
                      expense: exp,
                      formatter: formatter,
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
  const _ExpenseLine({required this.expense, required this.formatter});

  final Expense expense;
  final AppFormatters formatter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      dense: true,
      title: Text(expense.note ?? formatter.date(expense.tradeDate)),
      subtitle: Text(formatter.date(expense.tradeDate)),
      trailing: Text(
        formatter.currency(expense.amount, code: expense.currency),
        style: theme.textTheme.bodyMedium?.copyWith(
          fontFeatures: TypographyTokens.tabularFigures,
        ),
      ),
    );
  }
}

