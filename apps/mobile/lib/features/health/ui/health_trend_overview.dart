part of 'health_trend_page.dart';

class _TrendOverviewRow extends StatelessWidget {
  const _TrendOverviewRow({required this.series, required this.onPress});
  final HealthSeries series;
  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final kind = series.kind;
    final value = kind.formatValue(l, series.summary!);
    final date = healthDateLabel(l, series.latest!.day);
    return Semantics(
      button: true,
      label: '${kind.title(l)} $value $date',
      child: AppTappable(
        key: ValueKey('health-trend-${kind.name}'),
        onPress: onPress,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.s16),
          child: LayoutBuilder(
            builder: (context, constraints) => Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            kind.icon,
                            size: AppIconSizes.sm,
                            color: context.appTheme.categorical.adapt(
                              kind.accent,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.s8),
                          Expanded(
                            child: Text(
                              kind.title(l),
                              style: context.rowTitleStyle,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.s8),
                      Text(value, style: context.strongTitleStyle),
                      const SizedBox(height: AppSpacing.s4),
                      Text(
                        kind.isMeasurement ||
                                kind.chartStyle == HealthChartStyle.states
                            ? l.healthLatestRecordOn(date)
                            : '${l.healthAverageShort} · ${l.healthObservedDayAverage(series.recordedDays, series.window.days)}',
                        style: context.captionStyle,
                      ),
                    ],
                  ),
                ),
                if (series.samples.length > 1 &&
                    constraints.maxWidth >= 280 &&
                    kind.chartStyle != HealthChartStyle.states) ...[
                  const SizedBox(width: AppSpacing.s12),
                  SizedBox(
                    width: 88,
                    height: 40,
                    child: ExcludeSemantics(
                      child: HealthSeriesChart(series: series, compact: true),
                    ),
                  ),
                ],
                const SizedBox(width: AppSpacing.s8),
                Icon(
                  FLucideIcons.chevronRight,
                  size: AppIconSizes.sm,
                  color: context.theme.colors.mutedForeground,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TrendPeriodSummary extends StatelessWidget {
  const _TrendPeriodSummary({required this.series});
  final List<HealthSeries> series;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final comparable = series.where((s) => s.changePercent != null).toList()
      ..sort(
        (a, b) => b.changePercent!.abs().compareTo(a.changePercent!.abs()),
      );
    final window = series.first.window;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${healthDateLabel(l, window.start)} – ${healthDateLabel(l, window.today)}',
          style: context.captionStyle,
        ),
        const SizedBox(height: AppSpacing.s8),
        if (comparable.isEmpty)
          Text(l.healthComparisonNeedsHistory, style: context.bodyCaptionStyle)
        else ...[
          Wrap(
            spacing: AppSpacing.s12,
            runSpacing: AppSpacing.s8,
            children: [
              for (final item in comparable.take(2))
                Text(
                  '${item.kind.title(l)} ${_signedChange(item.changePercent!)}',
                  style: context.labelStyle,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.s4),
          Text(
            l.healthComparisonDefinition(window.days),
            style: context.captionStyle,
          ),
        ],
      ],
    );
  }
}

String _signedChange(double delta) =>
    '${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(1)}%';

class _MissingMetricRow extends StatelessWidget {
  const _MissingMetricRow({required this.kind, required this.onPress});
  final HealthMetricKind kind;
  final VoidCallback onPress;
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AppTappable(
      onPress: onPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.s12,
          horizontal: AppSpacing.s16,
        ),
        child: Row(
          children: [
            Expanded(child: Text(kind.title(l), style: context.captionStyle)),
            Text(l.healthNoData, style: context.captionStyle),
            const SizedBox(width: AppSpacing.s8),
            Icon(
              FLucideIcons.chevronRight,
              size: AppIconSizes.xs,
              color: context.theme.colors.mutedForeground,
            ),
          ],
        ),
      ),
    );
  }
}
