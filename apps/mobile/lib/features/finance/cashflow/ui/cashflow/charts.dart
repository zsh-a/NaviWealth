part of '../cashflow_page.dart';

class _ChartsPanel extends StatelessWidget {
  const _ChartsPanel({required this.model, required this.formatter});

  final _CashFlowViewModel model;
  final AppFormatters formatter;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final semantic = SemanticColors.of(context);
    final locale = Localizations.localeOf(context).toString();
    final axis = ValueAxis.currency(
      currencyCode: model.baseCurrency,
      showGrid: true,
      locale: locale,
    );
    return SoftCard(
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.cashFlowIncomeExpenseTitle, style: context.rowTitleStyle),
          const SizedBox(height: AppSpacing.s12),
          NwBarChart(
            series: [
              CategorySeries(
                name: l10n.cashFlowKpiInflow,
                data: model.periods
                    .map(
                      (period) => CategoryDatum(
                        label: period.label,
                        value: period.inflow.toDouble(),
                        colorOverride: semantic.success,
                      ),
                    )
                    .toList(),
              ),
              CategorySeries(
                name: l10n.cashFlowKpiOutflow,
                data: model.periods
                    .map(
                      (period) => CategoryDatum(
                        label: period.label,
                        value: period.outflow.toDouble(),
                        colorOverride: semantic.danger,
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
          const SizedBox(height: AppSpacing.s20),
          Text(l10n.cashFlowNetTrendTitle, style: context.rowTitleStyle),
          const SizedBox(height: AppSpacing.s12),
          SizedBox(
            height: AppChartHeights.full,
            child: NwLineChart(
              series: [
                ChartSeries(
                  name: l10n.cashFlowKpiNet,
                  points: model.periods
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
        ],
      ),
    );
  }
}

class _CategoryPanel extends StatelessWidget {
  const _CategoryPanel({required this.model, required this.formatter});

  final _CashFlowViewModel model;
  final AppFormatters formatter;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final slices = model.categories
        .map(
          (category) => Slice(
            label: _kindLabel(l10n, category.kind),
            value: category.amount.toDouble(),
          ),
        )
        .toList();
    return SoftCard(
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.cashFlowCategoryTitle, style: context.rowTitleStyle),
          const SizedBox(height: AppSpacing.s12),
          NwPieChart(
            slices: slices,
            aspectRatio: 4 / 3,
            semanticLabel: l10n.cashFlowCategoryTitle,
          ),
          const SizedBox(height: AppSpacing.s12),
          for (final category in model.categories)
            _CategoryRow(
              category: category,
              formatter: formatter,
              total: model.categoryTotal,
            ),
          if (model.categories.any((c) => c.kind == CashFlowKind.dividend))
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.s12),
              child: FButton(
                variant: FButtonVariant.outline,
                onPress: () => context.push(FinanceRoutes.cashflowDividends),
                prefix: const Icon(FLucideIcons.wallet),
                child: Text(l10n.cashFlowViewDividendCenter),
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
  });

  final _CategoryTotal category;
  final AppFormatters formatter;
  final Decimal total;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final percent = total == Decimal.zero
        ? 0
        : (category.amount / total).toDouble();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _kindLabel(l10n, category.kind),
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
        ],
      ),
    );
  }
}
