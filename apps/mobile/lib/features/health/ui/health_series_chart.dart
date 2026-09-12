import 'package:flutter/widgets.dart';

import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/health_series.dart';
import 'health_metric_presentation.dart';

/// Domain shaping around existing chart primitives. Calendar gaps and units
/// are explicit; Health never inherits market gain/loss tooltip semantics.
class HealthSeriesChart extends StatelessWidget {
  const HealthSeriesChart({
    super.key,
    required this.series,
    this.compact = false,
    this.onFocus,
  });
  final HealthSeries series;
  final bool compact;
  final ValueChanged<HealthDaySample?>? onFocus;

  static double _x(DateTime day) => DateTime(
    day.year,
    day.month,
    day.day,
    12,
  ).millisecondsSinceEpoch.toDouble();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final kind = series.kind;
    final accent = context.appTheme.categorical.adapt(kind.accent);
    final label =
        '${kind.title(l)} · ${l.healthWindowDays(series.window.days)}';
    if (series.samples.isEmpty) return const SizedBox.shrink();
    if (kind.chartStyle == HealthChartStyle.states) {
      return Align(
        alignment: AlignmentDirectional.centerStart,
        child: Wrap(
          spacing: AppSpacing.s6,
          runSpacing: AppSpacing.s6,
          children: [
            for (final sample in series.samples.reversed.take(compact ? 1 : 12))
              AppBadge(
                label: compact
                    ? kind.formatValue(l, sample.value)
                    : '${healthDateLabel(l, sample.day)} · ${kind.formatValue(l, sample.value)}',
                size: AppBadgeSize.compact,
              ),
          ],
        ),
      );
    }
    if (!compact && kind.chartStyle == HealthChartStyle.bars) {
      final byDay = {for (final sample in series.samples) sample.day: sample};
      final last = series.window.days - 1;
      return LayoutBuilder(
        builder: (context, constraints) {
          final scale = MediaQuery.textScalerOf(context).scale(1);
          final count = ((constraints.maxWidth - 44) / (80 * scale))
              .floor()
              .clamp(2, 4);
          final ticks = {
            for (var i = 0; i < count; i++) (last * i / (count - 1)).round(),
          };
          return NwBarChart(
            yAxis: ValueAxis(
              maxLabels: 3,
              showGrid: true,
              locale: l.localeName,
            ),
            semanticLabel: label,
            aspectRatio: constraints.maxWidth / AppChartHeights.full,
            barWidth: (constraints.maxWidth / series.window.days * 0.45).clamp(
              2,
              16,
            ),
            onScrub: (datum) => onFocus?.call(datum?.meta as HealthDaySample?),
            series: [
              CategorySeries(
                name: kind.title(l),
                colorOverride: accent,
                data: [
                  for (final (index, date) in series.window.dates.indexed)
                    CategoryDatum(
                      label: ticks.contains(index)
                          ? healthDateLabel(l, date)
                          : '',
                      tooltipLabel: healthDateLabel(l, date),
                      value: byDay[date]?.value ?? 0,
                      isMissing: !byDay.containsKey(date),
                      meta: byDay[date],
                    ),
                ],
              ),
            ],
          );
        },
      );
    }
    return NwLineChart(
      touchSelection: ChartTouchSelection.nearest,
      uniformSeriesStyle: true,
      semanticLabel: label,
      minX: _x(series.window.start) - const Duration(hours: 12).inMilliseconds,
      maxX: _x(series.window.today) + const Duration(hours: 12).inMilliseconds,
      xAxis: TimeAxis(
        format: AxisDateFormat.dayMonth,
        locale: l.localeName,
        maxLabels: MediaQuery.textScalerOf(context).scale(1) > 1.3 ? 2 : 4,
      ),
      yAxis: ValueAxis(maxLabels: 3, showGrid: !compact, locale: l.localeName),
      interpolation: ChartInterpolation.linear,
      showDots:
          series.samples.length <= 7 ||
          series.segments.any((segment) => segment.length == 1),
      downsample: false,
      minimal: compact,
      onScrubChanged: (state) =>
          onFocus?.call(state?.point.meta as HealthDaySample?),
      series: [
        for (final segment in series.segments)
          ChartSeries(
            name: kind.title(l),
            colorOverride: accent,
            strokeWidth: AppStroke.branch,
            points: [
              for (final sample in segment)
                ChartPoint(x: _x(sample.day), y: sample.value, meta: sample),
            ],
          ),
      ],
    );
  }
}
