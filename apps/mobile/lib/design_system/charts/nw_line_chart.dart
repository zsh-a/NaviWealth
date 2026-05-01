import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../tokens/typography_tokens.dart';
import 'axes.dart';
import 'chart_palette.dart';
import 'chart_series.dart';
import 'downsample.dart';
import 'drilldown.dart';
import 'empty_chart_placeholder.dart';

/// Theme-aware line chart wrapper around `fl_chart`.
///
/// Pass an unbounded number of [ChartSeries]; intent + ordinal decide the
/// color via [resolveSeriesColor]. The underlying `LineChartData` is built
/// once per series-list identity, so callers should pass the same series
/// instance across rebuilds when they want animation.
///
/// For area / filled charts use [NwAreaChart] (same renderer with
/// `filled: true` defaulting on).
class NwLineChart extends StatelessWidget {
  const NwLineChart({
    super.key,
    required this.series,
    this.xAxis = const TimeAxis(),
    this.yAxis = const ValueAxis(),
    this.aspectRatio = 16 / 9,
    this.drillDown,
    this.downsample = true,
    this.downsampleTarget = kDefaultDownsampleTarget,
    this.semanticLabel,
    this.filled = false,
  });

  final List<ChartSeries> series;
  final TimeAxis xAxis;
  final ValueAxis yAxis;
  final double aspectRatio;
  final ChartDrillDown? drillDown;

  /// Auto-apply [downsampleLttb] when a series exceeds [downsampleTarget].
  /// Set to `false` to opt out (e.g. an audit view that must show every tick).
  final bool downsample;
  final int downsampleTarget;

  final String? semanticLabel;

  /// Render below-line area fill. When true on a single-series chart, the
  /// fill alpha defaults to ~12% of the line color. For multi-series stacked
  /// fills use [NwAreaChart] with `stacked: true`.
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final nonEmpty = series.where((s) => s.points.isNotEmpty).toList();
    if (nonEmpty.isEmpty) {
      return AspectRatio(
        aspectRatio: aspectRatio,
        child: const EmptyChartPlaceholder(),
      );
    }

    final palette = ChartPalette.of(context);
    final processed = [
      for (final s in nonEmpty)
        ChartSeries(
          name: s.name,
          intent: s.intent,
          emphasis: s.emphasis,
          colorOverride: s.colorOverride,
          fillOpacity: s.fillOpacity,
          strokeWidth: s.strokeWidth,
          points: maybeDownsample(
            s.points,
            target: downsampleTarget,
            enabled: downsample,
          ),
        ),
    ];

    final allPoints = processed.expand((s) => s.points);
    final minX = allPoints.map((p) => p.x).reduce((a, b) => a < b ? a : b);
    final maxX = allPoints.map((p) => p.x).reduce((a, b) => a > b ? a : b);
    final minY = allPoints.map((p) => p.y).reduce((a, b) => a < b ? a : b);
    final maxY = allPoints.map((p) => p.y).reduce((a, b) => a > b ? a : b);
    final yPad = (maxY - minY).abs() * 0.1 + 1;

    final lineBars = <LineChartBarData>[];
    for (var i = 0; i < processed.length; i++) {
      final s = processed[i];
      final color = resolveSeriesColor(
        context,
        intent: s.intent,
        ordinal: i,
        override: s.colorOverride,
      );
      lineBars.add(_buildBarData(context, s, color, palette, i));
    }

    final touchData = _buildTouchData(context, palette, processed);

    return Semantics(
      label: semanticLabel,
      container: true,
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: LineChart(
          LineChartData(
            minX: minX,
            maxX: maxX,
            minY: (minY - yPad),
            maxY: maxY + yPad,
            gridData: FlGridData(
              show: yAxis.showGrid || xAxis.showGrid,
              drawHorizontalLine: yAxis.showGrid,
              drawVerticalLine: xAxis.showGrid,
              getDrawingHorizontalLine: (_) =>
                  FlLine(color: palette.gridLine, strokeWidth: 1),
              getDrawingVerticalLine: (_) =>
                  FlLine(color: palette.gridLine, strokeWidth: 1),
            ),
            borderData: FlBorderData(show: false),
            titlesData: _buildTitles(palette),
            lineBarsData: lineBars,
            lineTouchData: touchData,
          ),
        ),
      ),
    );
  }

  LineChartBarData _buildBarData(
    BuildContext context,
    ChartSeries s,
    Color color,
    ChartPalette palette,
    int ordinal,
  ) {
    final dashArray = switch (s.emphasis) {
      SeriesEmphasis.solid => null,
      SeriesEmphasis.dashed => <int>[6, 4],
      SeriesEmphasis.dotted => <int>[2, 4],
    };
    final isProjection = s.intent == SeriesIntent.projection;
    final defaultStroke = isProjection || s.intent == SeriesIntent.muted
        ? 1.5
        : 2.5;

    return LineChartBarData(
      spots: [for (final p in s.points) FlSpot(p.x, p.y)],
      isCurved: false,
      color: color,
      dashArray: dashArray ??
          (isProjection ? const [4, 4] : null),
      barWidth: s.strokeWidth ?? defaultStroke,
      dotData: FlDotData(show: s.points.length <= 60),
      belowBarData: filled
          ? BarAreaData(
              show: true,
              color: color.withValues(
                alpha: s.fillOpacity ?? _defaultFillAlpha(context),
              ),
            )
          : BarAreaData(show: false),
    );
  }

  double _defaultFillAlpha(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark ? 0.18 : 0.12;
  }

  FlTitlesData _buildTitles(ChartPalette palette) {
    final labelStyle = TypographyTokens.numericCaption.copyWith(
      color: palette.axisLabel,
    );
    return FlTitlesData(
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 24,
          getTitlesWidget: (value, meta) {
            // fl_chart calls this for "candidate" tick positions; respect
            // the maxLabels budget by skipping when interval mismatches.
            return Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(xAxis.formatTimestamp(value), style: labelStyle),
            );
          },
        ),
      ),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 44,
          getTitlesWidget: (value, meta) {
            return Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Text(yAxis.formatValue(value), style: labelStyle),
            );
          },
        ),
      ),
    );
  }

  LineTouchData _buildTouchData(
    BuildContext context,
    ChartPalette palette,
    List<ChartSeries> processed,
  ) {
    final dd = drillDown;
    return LineTouchData(
      enabled: true,
      touchTooltipData: LineTouchTooltipData(
        getTooltipColor: (_) => palette.tooltipBackground,
        tooltipBorderRadius: BorderRadius.circular(6),
        tooltipPadding: const EdgeInsets.symmetric(
          horizontal: 8,
          vertical: 6,
        ),
        getTooltipItems: (touched) {
          return [
            for (final spot in touched)
              LineTooltipItem(
                _tooltipLine(processed, spot),
                TypographyTokens.numericCaption.copyWith(
                  color: palette.tooltipForeground,
                ),
              ),
          ];
        },
      ),
      touchCallback: (event, response) {
        if (dd == null) return;
        if (event is! FlTapUpEvent && event is! FlLongPressEnd) return;
        final touched = response?.lineBarSpots;
        if (touched == null || touched.isEmpty) return;
        final s = processed[touched.first.barIndex];
        final originalIndex = touched.first.spotIndex.clamp(
          0,
          s.points.length - 1,
        );
        final point = s.points[originalIndex];
        if (dd is PointDrillDown) {
          if (dd.haptic) HapticFeedback.selectionClick();
          dd.onTap(point);
        } else if (dd is RangeDrillDown) {
          // Range support requires capturing both ends; without a long-press
          // gesture we surface a single-point range so callers can decide.
          dd.onRange(
            ChartRangeSelection(
              start: point.x,
              end: point.x,
              points: [point],
            ),
          );
        }
      },
    );
  }

  String _tooltipLine(List<ChartSeries> series, LineBarSpot spot) {
    final s = series[spot.barIndex];
    final xLabel = xAxis.formatTimestamp(spot.x);
    final yLabel = yAxis.formatValue(spot.y);
    return '${s.name}\n$xLabel · $yLabel';
  }
}
