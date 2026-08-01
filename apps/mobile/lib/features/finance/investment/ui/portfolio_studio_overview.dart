part of 'portfolio_hub_page.dart';

class _StudioOverview extends ConsumerStatefulWidget {
  const _StudioOverview({
    required this.portfolio,
    required this.portfolioNode,
    required this.sleeves,
    required this.tree,
  });

  final InvestmentPortfolio portfolio;
  final AllocationNode portfolioNode;
  final List<AllocationNode> sleeves;
  final PortfolioAllocationTree tree;

  @override
  ConsumerState<_StudioOverview> createState() => _StudioOverviewState();
}

class _StudioOverviewState extends ConsumerState<_StudioOverview> {
  PortfolioTrendRange _range = PortfolioTrendRange.month;
  PortfolioTrendMetric _metric = PortfolioTrendMetric.marketValue;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final trend = ref.watch(
      portfolioTrendProvider(
        PortfolioTrendRequest(portfolioId: widget.portfolio.id, range: _range),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StudioSectionHeader(
          title: l10n.portfolioTrendTitle,
          subtitle: l10n.portfolioTrendHint,
        ),
        const SizedBox(height: AppSpacing.s8),
        SoftCard.raised(
          padding: const EdgeInsets.all(AppSpacing.s16),
          child: _PortfolioTrendPanel(
            trend: trend,
            metric: _metric,
            range: _range,
            onMetricChanged: (metric) => setState(() => _metric = metric),
            onRangeChanged: (range) => setState(() => _range = range),
            onRetry: () => ref.invalidate(
              portfolioTrendProvider(
                PortfolioTrendRequest(
                  portfolioId: widget.portfolio.id,
                  range: _range,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.s16),
        _StudioSectionHeader(
          title: l10n.portfolioStudioAllocationTitle,
          subtitle: l10n.portfolioStudioAllocationHint,
        ),
        const SizedBox(height: AppSpacing.s8),
        _AllocationPathCard(
          portfolioNode: widget.portfolioNode,
          sleeves: widget.sleeves,
          tree: widget.tree,
        ),
        const SizedBox(height: AppSpacing.s16),
        _StudioSectionHeader(
          title: l10n.portfolioStudioNextActionTitle,
          subtitle: l10n.portfolioStudioNextActionHint,
        ),
        const SizedBox(height: AppSpacing.s8),
        FButton(
          variant: FButtonVariant.outline,
          onPress: () async {
            final groups = await ref.read(
              portfolioRebalanceGroupsProvider.future,
            );
            final scoped = groups
                .where((group) => group.portfolioId == widget.portfolio.id)
                .toList(growable: false);
            if (!context.mounted || scoped.isEmpty) return;
            await showStrategySleeveAllocationEditor(context, ref, scoped);
          },
          prefix: const Icon(FLucideIcons.slidersHorizontal),
          child: Text(l10n.portfolioStrategyAllocationEditTitle),
        ),
      ],
    );
  }
}

class _PortfolioTrendPanel extends StatelessWidget {
  const _PortfolioTrendPanel({
    required this.trend,
    required this.metric,
    required this.range,
    required this.onMetricChanged,
    required this.onRangeChanged,
    required this.onRetry,
  });

  final AsyncValue<PortfolioTrendSeries?> trend;
  final PortfolioTrendMetric metric;
  final PortfolioTrendRange range;
  final ValueChanged<PortfolioTrendMetric> onMetricChanged;
  final ValueChanged<PortfolioTrendRange> onRangeChanged;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedRow<PortfolioTrendMetric>(
          options: PortfolioTrendMetric.values,
          value: metric,
          minSegmentWidth: 88,
          labelOf: (item) => switch (item) {
            PortfolioTrendMetric.marketValue => l10n.portfolioTrendMarketValue,
            PortfolioTrendMetric.performance => l10n.portfolioTrendPerformance,
          },
          onChanged: onMetricChanged,
        ),
        const SizedBox(height: AppSpacing.s16),
        ContentCrossFade(
          child: KeyedSubtree(
            key: ValueKey('${range.name}-${metric.name}'),
            child: trend.when(
              loading: () => const _PortfolioTrendSkeleton(),
              error: (_, _) => _PortfolioTrendError(onRetry: onRetry),
              data: (series) => series == null
                  ? const _PortfolioTrendEmpty()
                  : _PortfolioTrendChart(series: series, metric: metric),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.s16),
        SegmentedRow<PortfolioTrendRange>(
          options: PortfolioTrendRange.values,
          value: range,
          minSegmentWidth: 48,
          labelOf: (item) => switch (item) {
            PortfolioTrendRange.month => l10n.dashboardRange1M,
            PortfolioTrendRange.quarter => l10n.dashboardRange3M,
            PortfolioTrendRange.yearToDate => l10n.portfolioTrendRangeYtd,
            PortfolioTrendRange.year => l10n.dashboardRange1Y,
            PortfolioTrendRange.all => l10n.dashboardRangeAll,
          },
          onChanged: onRangeChanged,
        ),
      ],
    );
  }
}

class _PortfolioTrendChart extends StatelessWidget {
  const _PortfolioTrendChart({required this.series, required this.metric});

  final PortfolioTrendSeries series;
  final PortfolioTrendMetric metric;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final chart = PortfolioTrendChartProjection.fromSeries(
      series: series,
      metric: metric,
    );
    if (!chart.isRenderable) {
      return const _PortfolioTrendEmpty();
    }

    final chartPoints = [
      for (final datum in chart.data)
        ChartPoint(
          x: datum.asOf.millisecondsSinceEpoch.toDouble(),
          y: datum.value,
          meta: datum.source,
        ),
    ];
    final periodPerformance = series.periodPerformanceRatio;
    final changeIntent = chart.isDown ? SeriesIntent.down : SeriesIntent.up;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _PortfolioTrendMetric(
                label: l10n.portfolioTrendCurrentValue,
                child: MoneyText(
                  amount: series.currentValue.toDouble(),
                  currencyCode: series.baseCurrency,
                  compact: true,
                  style: TypographyTokens.numericTitleStrong,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.s12),
            Expanded(
              child: _PortfolioTrendMetric(
                label: l10n.portfolioTrendPeriodPerformance,
                child: periodPerformance == null
                    ? Text('—', style: TypographyTokens.numericBodyStrong)
                    : DeltaText.percentFromRatio(
                        ratio: periodPerformance,
                        fractionDigits: 1,
                        showIcon: false,
                        style: TypographyTokens.numericBodyStrong,
                      ),
              ),
            ),
            const SizedBox(width: AppSpacing.s12),
            Expanded(
              child: _PortfolioTrendMetric(
                label: l10n.portfolioTrendNetFlow,
                child: DeltaText(
                  value: series.periodNetFlow.toDouble(),
                  format: DeltaFormat.currency,
                  currencyCode: series.baseCurrency,
                  fractionDigits: 0,
                  showIcon: false,
                  style: TypographyTokens.numericBodyStrong,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.s16),
        SizedBox(
          key: const ValueKey('portfolio-trend-chart'),
          height: AppChartHeights.standard,
          child: NwLineChart(
            series: [
              ChartSeries(
                name: metric == PortfolioTrendMetric.marketValue
                    ? l10n.portfolioTrendMarketValue
                    : l10n.portfolioTrendPerformance,
                points: chartPoints,
                intent: changeIntent,
                fillOpacity: AppOpacity.light,
              ),
            ],
            xAxis: TimeAxis(
              format: switch (chart.axisGranularity) {
                PortfolioTrendAxisGranularity.dayMonth =>
                  AxisDateFormat.dayMonth,
                PortfolioTrendAxisGranularity.monthYear =>
                  AxisDateFormat.monthYear,
                PortfolioTrendAxisGranularity.yearOnly =>
                  AxisDateFormat.yearOnly,
              },
              maxLabels: 4,
            ),
            yAxis: metric == PortfolioTrendMetric.marketValue
                ? ValueAxis.currency(
                    currencyCode: series.baseCurrency,
                    maxLabels: 3,
                    showGrid: true,
                  )
                : ValueAxis.percent(
                    fractionDigits: 1,
                    maxLabels: 3,
                    showGrid: true,
                  ),
            filled: true,
            interpolation: ChartInterpolation.linear,
            showDots: false,
            heroDots: true,
            showYAxis: false,
            showTouchXAxisLabel: true,
            semanticLabel: l10n.portfolioTrendChartSemantics,
          ),
        ),
        if (series.hasEstimatedPoints) ...[
          const SizedBox(height: AppSpacing.s10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                FLucideIcons.info,
                size: AppIconSizes.sm,
                color: context.theme.colors.mutedForeground,
              ),
              const SizedBox(width: AppSpacing.s6),
              Expanded(
                child: Text(
                  l10n.portfolioTrendEstimatedDisclosure,
                  style: context.microCaptionStyle,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _PortfolioTrendMetric extends StatelessWidget {
  const _PortfolioTrendMetric({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: context.microCaptionStyle),
        const SizedBox(height: AppSpacing.s4),
        child,
      ],
    );
  }
}

class _PortfolioTrendEmpty extends StatelessWidget {
  const _PortfolioTrendEmpty();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AppChartHeights.standard,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              FLucideIcons.chartNoAxesCombined,
              color: context.theme.colors.mutedForeground,
            ),
            const SizedBox(height: AppSpacing.s8),
            Text(
              AppLocalizations.of(context).portfolioTrendAwaitingData,
              textAlign: TextAlign.center,
              style: context.bodyCaptionStyle,
            ),
          ],
        ),
      ),
    );
  }
}

class _PortfolioTrendSkeleton extends StatelessWidget {
  const _PortfolioTrendSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        Row(
          children: [
            Expanded(child: SkeletonBox(height: AppSpacing.s48)),
            SizedBox(width: AppSpacing.s12),
            Expanded(child: SkeletonBox(height: AppSpacing.s48)),
            SizedBox(width: AppSpacing.s12),
            Expanded(child: SkeletonBox(height: AppSpacing.s48)),
          ],
        ),
        SizedBox(height: AppSpacing.s16),
        SkeletonBox(height: AppChartHeights.standard),
      ],
    );
  }
}

class _PortfolioTrendError extends StatelessWidget {
  const _PortfolioTrendError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SizedBox(
      height: AppChartHeights.standard,
      child: Center(
        child: FButton(
          variant: FButtonVariant.ghost,
          onPress: onRetry,
          prefix: const Icon(FLucideIcons.refreshCw),
          child: Text(l10n.commonRetry),
        ),
      ),
    );
  }
}
