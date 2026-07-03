part of 'trend_card.dart';

class _TrendChart extends StatelessWidget {
  const _TrendChart({
    required this.trend,
    this.fillAvailableHeight = false,
    this.showSummary = true,
    this.showYAxis = false,
  });

  final DashboardTrend trend;
  final bool fillAvailableHeight;
  final bool showSummary;
  final bool showYAxis;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final aspect = chartAspectFor(constraints.maxWidth);
        if (trend.isEmpty) {
          return AspectRatio(
            aspectRatio: aspect,
            child: const EmptyChartPlaceholder(),
          );
        }
        final allFlat = trend.points.every(
          (p) => p.netWorth.amount == trend.points.first.netWorth.amount,
        );

        // Flat series (e.g. brand-new account, no history yet) carries no
        // analytical signal. Drawing a full chart for it produced a
        // misleading +/-1 axis, a dotted line and a heavy gradient block
        // that collided with the caption. Instead show a calm, centered
        // baseline: endpoints only, no axis numbers, no fill - it reads
        // as "steady / awaiting data" and morphs into the real chart the
        // moment values start moving.
        if (allFlat) {
          final flat = trend.points;
          final flatSeries = ChartSeries(
            name: 'netWorth',
            points: [
              ChartPoint(
                x: flat.first.asOf.millisecondsSinceEpoch.toDouble(),
                y: flat.first.netWorth.amount.toDouble(),
                meta: flat.first,
              ),
              ChartPoint(
                x: flat.last.asOf.millisecondsSinceEpoch.toDouble(),
                y: flat.last.netWorth.amount.toDouble(),
                meta: flat.last,
              ),
            ],
          );
          final flatChart = NwLineChart(
            series: [flatSeries],
            minimal: true,
            interpolation: ChartInterpolation.linear,
            showDots: false,
            semanticLabel: AppLocalizations.of(context).dashboardTrendTitle,
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (fillAvailableHeight)
                Expanded(child: flatChart)
              else
                SizedBox(height: AppChartHeights.mini, child: flatChart),
              const SizedBox(height: AppSpacing.s12),
              Text(
                AppLocalizations.of(context).dashboardTrendFlatHint,
                style: context.captionStyle.copyWith(height: 1.4),
              ),
            ],
          );
        }

        final points = [
          for (final p in trend.points)
            ChartPoint(
              x: p.asOf.millisecondsSinceEpoch.toDouble(),
              y: p.netWorth.amount.toDouble(),
              meta: p,
            ),
        ];
        final series = ChartSeries(name: 'netWorth', points: points);
        final dateFmt = trend.range.spanDays <= 30
            ? AxisDateFormat.dayMonth
            : trend.range.spanDays <= 730
            ? AxisDateFormat.monthYear
            : AxisDateFormat.yearOnly;
        final chart = _LineChartBody(
          series: series,
          trend: trend,
          dateFmt: dateFmt,
          showYAxis: showYAxis,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showSummary) ...[
              _TrendSummary(trend: trend),
              const SizedBox(height: AppSpacing.s16),
            ],
            if (fillAvailableHeight)
              Expanded(child: chart)
            else
              SizedBox(height: AppChartHeights.full, child: chart),
          ],
        );
      },
    );
  }
}

class _LineChartBody extends StatelessWidget {
  const _LineChartBody({
    required this.series,
    required this.trend,
    required this.dateFmt,
    required this.showYAxis,
  });

  final ChartSeries series;
  final DashboardTrend trend;
  final AxisDateFormat dateFmt;
  final bool showYAxis;

  @override
  Widget build(BuildContext context) {
    final chartSeries = ChartSeries(
      name: AppLocalizations.of(context).dashboardTrendTitle,
      points: series.points,
      intent: SeriesIntent.primary,
      fillOpacity: AppOpacity.subtle,
      strokeWidth: AppStroke.medium,
    );
    return NwLineChart(
      series: [chartSeries],
      xAxis: TimeAxis(format: dateFmt, maxLabels: 4),
      yAxis: ValueAxis.currency(
        currencyCode: trend.baseCurrency,
        maxLabels: 3,
        showGrid: true,
      ),
      filled: true,
      interpolation: ChartInterpolation.linear,
      showDots: false,
      heroDots: false,
      showXAxis: true,
      showYAxis: showYAxis,
      showTouchXAxisLabel: true,
      semanticLabel: AppLocalizations.of(context).dashboardTrendTitle,
    );
  }
}
