import 'package:flutter/widgets.dart';

import 'axes.dart';
import 'chart_series.dart';
import 'downsample.dart';
import 'drilldown.dart';
import 'nw_line_chart.dart';

/// Filled-area variant of [NwLineChart]. Single-series → simple area chart;
/// `stacked: true` with multiple series → cumulative stacked area.
///
/// Implementation note: stacking is done by transforming the input series
/// into running cumulative Y values before delegating to the line renderer,
/// which keeps a single touch / tooltip / drill-down code path.
class NwAreaChart extends StatelessWidget {
  const NwAreaChart({
    super.key,
    required this.series,
    this.xAxis = const TimeAxis(),
    this.yAxis = const ValueAxis(),
    this.aspectRatio = 16 / 9,
    this.drillDown,
    this.downsample = true,
    this.downsampleTarget = kDefaultDownsampleTarget,
    this.semanticLabel,
    this.stacked = false,
  });

  final List<ChartSeries> series;
  final TimeAxis xAxis;
  final ValueAxis yAxis;
  final double aspectRatio;
  final ChartDrillDown? drillDown;
  final bool downsample;
  final int downsampleTarget;
  final String? semanticLabel;
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    final input = stacked ? _cumulate(series) : series;
    return NwLineChart(
      series: input,
      xAxis: xAxis,
      yAxis: yAxis,
      aspectRatio: aspectRatio,
      drillDown: drillDown,
      downsample: downsample,
      downsampleTarget: downsampleTarget,
      semanticLabel: semanticLabel,
      filled: true,
    );
  }

  /// Stacked area: at each shared X, sum lower-index series' Y values.
  /// Assumes series share the same X grid (callers should align /
  /// interpolate beforehand if not).
  static List<ChartSeries> _cumulate(List<ChartSeries> series) {
    if (series.isEmpty) return series;
    final out = <ChartSeries>[];
    final running = <double, double>{};
    for (final s in series) {
      final newPoints = <ChartPoint>[];
      for (final p in s.points) {
        final base = running[p.x] ?? 0;
        final stacked = base + p.y;
        running[p.x] = stacked;
        newPoints.add(ChartPoint(x: p.x, y: stacked, meta: p.meta));
      }
      out.add(
        ChartSeries(
          name: s.name,
          intent: s.intent,
          emphasis: s.emphasis,
          colorOverride: s.colorOverride,
          fillOpacity: s.fillOpacity,
          strokeWidth: s.strokeWidth,
          points: newPoints,
        ),
      );
    }
    return out;
  }
}
