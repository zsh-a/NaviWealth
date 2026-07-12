import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../tokens/dimens_tokens.dart';
import '../tokens/typography_tokens.dart';
import 'axes.dart';
import 'chart_palette.dart';
import 'chart_series.dart';
import 'drilldown.dart';
import 'empty_chart_placeholder.dart';

/// Theme-aware bar chart wrapper around `fl_chart`.
///
/// - Single [series] with grouped data → simple bar chart (one bar per
///   category).
/// - Multiple [series] aligned on the same category labels → grouped bars
///   (default) or stacked bars (`stacked: true`).
///
/// Categories must align by index. Callers should pad missing categories
/// with `value: 0` rather than relying on label matching.
class NwBarChart extends StatelessWidget {
  const NwBarChart({
    super.key,
    required this.series,
    this.yAxis = const ValueAxis(),
    this.aspectRatio = 16 / 9,
    this.drillDown,
    this.stacked = false,
    this.barWidth = 16,
    this.semanticLabel,
  });

  final List<CategorySeries> series;
  final ValueAxis yAxis;
  final double aspectRatio;
  final ChartDrillDown? drillDown;
  final bool stacked;
  final double barWidth;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    if (series.isEmpty || series.every((s) => s.data.isEmpty)) {
      return AspectRatio(
        aspectRatio: aspectRatio,
        child: const EmptyChartPlaceholder(),
      );
    }

    final palette = ChartPalette.of(context);
    final categoryCount = series
        .map((s) => s.data.length)
        .reduce((a, b) => a > b ? a : b);

    // Pre-resolve series colors.
    final colors = <Color>[
      for (var i = 0; i < series.length; i++)
        resolveSeriesColor(
          context,
          intent: series[i].intent,
          ordinal: i,
          override: series[i].colorOverride,
        ),
    ];

    final groups = <BarChartGroupData>[];
    double maxY = 0;
    double minY = 0;
    for (var ci = 0; ci < categoryCount; ci++) {
      double stackTop = 0;
      double stackBottom = 0;
      final rods = <BarChartRodData>[];
      if (stacked) {
        // Build a single rod with stacked items.
        final stackItems = <BarChartRodStackItem>[];
        for (var si = 0; si < series.length; si++) {
          final datum = ci < series[si].data.length
              ? series[si].data[ci]
              : null;
          if (datum == null) continue;
          final color = datum.colorOverride ?? colors[si];
          if (datum.value >= 0) {
            stackItems.add(
              BarChartRodStackItem(stackTop, stackTop + datum.value, color),
            );
            stackTop += datum.value;
          } else {
            stackItems.add(
              BarChartRodStackItem(
                stackBottom + datum.value,
                stackBottom,
                color,
              ),
            );
            stackBottom += datum.value;
          }
        }
        rods.add(
          BarChartRodData(
            toY: stackTop,
            fromY: stackBottom,
            width: barWidth,
            rodStackItems: stackItems,
            borderRadius: const BorderRadius.all(Radius.circular(AppRadius.sm)),
          ),
        );
        if (stackTop > maxY) maxY = stackTop;
        if (stackBottom < minY) minY = stackBottom;
      } else {
        for (var si = 0; si < series.length; si++) {
          final datum = ci < series[si].data.length
              ? series[si].data[ci]
              : null;
          if (datum == null) continue;
          final color = datum.colorOverride ?? colors[si];
          rods.add(
            BarChartRodData(
              toY: datum.value,
              width: barWidth,
              color: color,
              borderRadius: const BorderRadius.all(
                Radius.circular(AppRadius.sm),
              ),
            ),
          );
          if (datum.value > maxY) maxY = datum.value;
          if (datum.value < minY) minY = datum.value;
        }
      }
      groups.add(BarChartGroupData(x: ci, barRods: rods));
    }

    final yPad = (maxY - minY).abs() * 0.1 + 1;
    final chartMinY = minY < 0 ? minY - yPad : 0.0;
    final chartMaxY = maxY + yPad;
    final yRange = (chartMaxY - chartMinY).abs();

    return Semantics(
      label: semanticLabel,
      container: true,
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: RepaintBoundary(
          child: BarChart(
            BarChartData(
              barGroups: groups,
              minY: chartMinY,
              maxY: chartMaxY,
              gridData: FlGridData(
                show: yAxis.showGrid,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (_) => FlLine(
                  color: palette.gridLine,
                  strokeWidth: AppStroke.hairline,
                ),
              ),
              borderData: FlBorderData(show: false),
              titlesData: _buildTitles(palette, yRange),
              barTouchData: _buildTouchData(context, palette, colors),
            ),
          ),
        ),
      ),
    );
  }

  FlTitlesData _buildTitles(ChartPalette palette, double yRange) {
    final labelStyle = TypographyTokens.numericCaption.copyWith(
      color: palette.axisLabel,
    );
    return FlTitlesData(
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 28,
          getTitlesWidget: (value, meta) {
            final ci = value.toInt();
            // Use the first non-empty series for category labels.
            final source = series.firstWhere(
              (s) => s.data.length > ci,
              orElse: () => series.first,
            );
            if (ci < 0 || ci >= source.data.length) return const SizedBox();
            return Padding(
              padding: const EdgeInsets.only(top: AppSpacing.s4),
              child: Text(
                source.data[ci].label,
                style: labelStyle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            );
          },
        ),
      ),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 44,
          getTitlesWidget: (value, meta) {
            if (!shouldRenderAxisLabel(
              value: value,
              meta: meta,
              range: yRange,
              maxLabels: yAxis.maxLabels,
            )) {
              return const SizedBox.shrink();
            }
            return Padding(
              padding: const EdgeInsets.only(right: AppSpacing.s4),
              child: Text(
                yAxis.formatValue(value),
                style: labelStyle,
                maxLines: 1,
                softWrap: false,
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
              ),
            );
          },
        ),
      ),
    );
  }

  BarTouchData _buildTouchData(
    BuildContext context,
    ChartPalette palette,
    List<Color> colors,
  ) {
    final dd = drillDown;
    return BarTouchData(
      enabled: true,
      touchTooltipData: BarTouchTooltipData(
        getTooltipColor: (_) => palette.tooltipBackground,
        tooltipBorderRadius: BorderRadius.circular(AppRadius.sm),
        tooltipPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s8,
          vertical: AppSpacing.s6,
        ),
        getTooltipItem: (group, groupIndex, rod, rodIndex) {
          final ci = group.x;
          final si = stacked ? rodIndex : rodIndex;
          if (si >= series.length) return null;
          final source = series[si];
          if (ci >= source.data.length) return null;
          final datum = source.data[ci];
          return BarTooltipItem(
            '${source.name}\n${datum.label} · ${yAxis.formatValue(datum.value)}',
            TypographyTokens.numericCaption.copyWith(
              color: palette.tooltipForeground,
            ),
          );
        },
      ),
      touchCallback: (event, response) {
        if (dd is! BarDrillDown) return;
        if (event is! FlTapUpEvent) return;
        final spot = response?.spot;
        if (spot == null) return;
        final ci = spot.touchedBarGroup.x;
        // For stacked, the touched stack item index identifies the series
        // that owns the segment under the finger; for grouped bars, the
        // rod index does the same.
        final si = stacked
            ? (spot.touchedStackItemIndex >= 0 ? spot.touchedStackItemIndex : 0)
            : spot.touchedRodDataIndex;
        if (si >= series.length || ci >= series[si].data.length) return;
        final datum = series[si].data[ci];
        if (dd.haptic) HapticFeedback.selectionClick();
        dd.onTap(datum);
      },
    );
  }
}
