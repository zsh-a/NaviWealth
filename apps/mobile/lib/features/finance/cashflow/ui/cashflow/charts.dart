part of '../cashflow_page.dart';

enum _CashFlowTrendMode { incomeExpense, net }

class _ChartsPanel extends StatefulWidget {
  const _ChartsPanel({required this.model, required this.formatter});

  final _CashFlowViewModel model;
  final AppFormatters formatter;

  @override
  State<_ChartsPanel> createState() => _ChartsPanelState();
}

class _ChartsPanelState extends State<_ChartsPanel> {
  _CashFlowTrendMode _mode = _CashFlowTrendMode.incomeExpense;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final status = context.appTheme.status;
    final locale = Localizations.localeOf(context).toString();
    final media = MediaQuery.of(context);
    final compactLabels =
        Breakpoints.isMobile(media.size.width) ||
        media.textScaler.scale(1) > 1.3;
    final axis = ValueAxis.currency(
      currencyCode: widget.model.baseCurrency,
      showGrid: true,
      locale: locale,
    );
    return SoftCard.raised(
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedRow<_CashFlowTrendMode>(
            options: _CashFlowTrendMode.values,
            value: _mode,
            minSegmentWidth: 96,
            labelOf: (mode) => switch (mode) {
              _CashFlowTrendMode.incomeExpense =>
                compactLabels
                    ? '${l10n.cashFlowKpiInflow} / ${l10n.cashFlowKpiOutflow}'
                    : l10n.cashFlowIncomeExpenseTitle,
              _CashFlowTrendMode.net => l10n.cashFlowKpiNet,
            },
            semanticLabelOf: (mode) => switch (mode) {
              _CashFlowTrendMode.incomeExpense =>
                l10n.cashFlowIncomeExpenseTitle,
              _CashFlowTrendMode.net => l10n.cashFlowNetTrendTitle,
            },
            onChanged: (mode) => setState(() => _mode = mode),
          ),
          const SizedBox(height: AppSpacing.s12),
          AnimatedSwitcher(
            duration: AppMotionPolicy.duration(context, Motion.fast),
            child: switch (_mode) {
              _CashFlowTrendMode.incomeExpense => NwBarChart(
                key: const ValueKey('cash-flow-income-expense-chart'),
                series: [
                  CategorySeries(
                    name: l10n.cashFlowKpiInflow,
                    data: widget.model.periods
                        .map(
                          (period) => CategoryDatum(
                            label: _cashFlowAxisLabel(
                              period.label,
                              compact: compactLabels,
                            ),
                            tooltipLabel: period.label,
                            value: period.inflow.toDouble(),
                            colorOverride: status.success.fg,
                          ),
                        )
                        .toList(),
                  ),
                  CategorySeries(
                    name: l10n.cashFlowKpiOutflow,
                    data: widget.model.periods
                        .map(
                          (period) => CategoryDatum(
                            label: _cashFlowAxisLabel(
                              period.label,
                              compact: compactLabels,
                            ),
                            tooltipLabel: period.label,
                            value: period.outflow.toDouble(),
                            colorOverride: status.danger.fg,
                          ),
                        )
                        .toList(),
                  ),
                ],
                yAxis: axis,
                aspectRatio: 16 / 7,
                barWidth: 10,
                semanticLabel: l10n.cashFlowIncomeExpenseTitle,
              ),
              _CashFlowTrendMode.net => SizedBox(
                key: const ValueKey('cash-flow-net-chart'),
                height: AppChartHeights.full,
                child: NwLineChart(
                  series: [
                    ChartSeries(
                      name: l10n.cashFlowKpiNet,
                      points: widget.model.periods
                          .map(
                            (period) => ChartPoint(
                              x: period.date.millisecondsSinceEpoch.toDouble(),
                              y: period.net.toDouble(),
                            ),
                          )
                          .toList(),
                      colorOverride: context.theme.colors.primary,
                    ),
                  ],
                  xAxis: TimeAxis(locale: locale, showGrid: false),
                  yAxis: axis,
                  interpolation: ChartInterpolation.linear,
                  semanticLabel: l10n.cashFlowNetTrendTitle,
                ),
              ),
            },
          ),
        ],
      ),
    );
  }
}

String _cashFlowAxisLabel(String label, {required bool compact}) {
  if (!compact) return label;
  final separator = label.contains('-') ? '-' : ' ';
  if (label.contains(separator)) return label.split(separator).last;
  if (label.length == 4 && int.tryParse(label) != null) {
    return label.substring(2);
  }
  return label;
}

class _IncomeSourcesPanel extends StatelessWidget {
  const _IncomeSourcesPanel({
    required this.model,
    required this.formatter,
    required this.onOpenCategory,
  });

  final _CashFlowViewModel model;
  final AppFormatters formatter;
  final ValueChanged<_CategoryTotal> onOpenCategory;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final categories = model.categories;
    final total = categories.fold<Decimal>(
      Decimal.zero,
      (sum, category) => sum + category.amount,
    );
    final slices = categories
        .map(
          (category) => Slice(
            label: category.label ?? _kindLabel(l10n, category.kind),
            value: category.amount.toDouble(),
          ),
        )
        .toList();
    return SoftCard.raised(
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.cashFlowCategoryIncome,
            style: context.theme.typography.body.md,
          ),
          const SizedBox(height: AppSpacing.s12),
          if (categories.isEmpty)
            const SizedBox(
              height: AppChartHeights.standard,
              child: EmptyChartPlaceholder(),
            )
          else
            NwPieChart(
              slices: slices,
              aspectRatio: 4 / 3,
              semanticLabel: l10n.cashFlowCategoryTitle,
            ),
          const SizedBox(height: AppSpacing.s12),
          for (final category in categories)
            _CategoryRow(
              category: category,
              formatter: formatter,
              total: total,
              onPress: () => onOpenCategory(category),
            ),
          if (categories.any((c) => c.kind == CashFlowKind.dividend))
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.s12),
              child: FButton(
                variant: FButtonVariant.outline,
                onPress: () => context.push(FinanceRoutes.cashflowDividends),
                prefix: MediaQuery.textScalerOf(context).scale(1) > 1.3
                    ? null
                    : const Icon(FLucideIcons.wallet),
                child: Flexible(
                  child: Text(
                    l10n.cashFlowViewDividendCenter,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.category,
    required this.formatter,
    required this.total,
    required this.onPress,
  });

  final _CategoryTotal category;
  final AppFormatters formatter;
  final Decimal total;
  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final percent = total == Decimal.zero
        ? 0
        : (category.amount / total).toDouble();
    return AppTappable(
      onPress: onPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.s8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                category.label ?? _kindLabel(l10n, category.kind),
                style: context.theme.typography.body.sm,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              formatter.percent(percent, decimalDigits: 0),
              style: context.captionStyle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(width: AppSpacing.s12),
            Flexible(
              child: Text(
                formatter.currency(category.amount, code: category.currency),
                style: TypographyTokens.numericBody.copyWith(
                  color: context.theme.colors.foreground,
                ),
                textAlign: TextAlign.end,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: AppSpacing.s6),
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
