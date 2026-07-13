import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forui/forui.dart';

import '../theme/market_colors.dart';
import '../tokens/dimens_tokens.dart';
import '../tokens/typography_tokens.dart';
import '../widgets/amount_privacy_placeholder.dart';
import '../widgets/amount_privacy_scope.dart';
import 'axes.dart';
import 'chart_palette.dart';
import 'chart_series.dart';
import 'downsample.dart';
import 'drilldown.dart';
import 'empty_chart_placeholder.dart';

part 'nw_line_chart_axes.dart';
part 'nw_line_chart_bars.dart';
part 'nw_line_chart_data.dart';
part 'nw_line_chart_models.dart';
part 'nw_line_chart_touch.dart';

const double _kLeftTitleReservedSize = 44;
const double _kBottomTitleReservedSize = 24;

/// Theme-aware line chart wrapper around `fl_chart`.
///
/// Pass an unbounded number of [ChartSeries]; intent + ordinal decide the
/// color via [resolveSeriesColor]. The underlying `LineChartData` is built
/// once per series-list identity, so callers should pass the same series
/// instance across rebuilds when they want animation.
///
/// For area / filled charts use [NwAreaChart] (same renderer with
/// `filled: true` defaulting on).
class NwLineChart extends StatefulWidget {
  const NwLineChart({
    super.key,
    required this.series,
    this.xAxis = const TimeAxis(),
    this.yAxis = const ValueAxis(),
    this.aspectRatio,
    this.drillDown,
    this.downsample = true,
    this.downsampleTarget = kDefaultDownsampleTarget,
    this.semanticLabel,
    this.filled = false,
    this.interpolation = ChartInterpolation.curved,
    this.curved,
    this.curveSmoothness = 0.28,
    this.heroDots = false,
    this.showDots,
    this.showXAxis = true,
    this.showYAxis = true,
    this.showTouchXAxisLabel = false,
    this.minimal = false,
    this.onScrub,
    this.minX,
    this.maxX,
  });

  final List<ChartSeries> series;
  final TimeAxis xAxis;
  final ValueAxis yAxis;
  final double? aspectRatio;
  final ChartDrillDown? drillDown;

  /// Live scrub sample while the user pans/long-presses. `null` on release.
  final ValueChanged<ChartPoint?>? onScrub;

  /// Optional forced X bounds (e.g. pin to a selected date range so sparse
  /// history leaves a calm empty lead-in instead of stretching the line).
  final double? minX;
  final double? maxX;

  /// Auto-apply [downsampleLttb] when a series exceeds [downsampleTarget].
  /// Set to `false` to opt out (e.g. an audit view that must show every tick).
  final bool downsample;
  final int downsampleTarget;

  final String? semanticLabel;

  /// Render below-line area fill. When true on a single-series chart, the
  /// fill uses a gradient from 70% of the line color to transparent.
  /// For multi-series stacked fills use [NwAreaChart] with `stacked: true`.
  final bool filled;

  /// Line interpolation mode. Keep [ChartInterpolation.curved] for
  /// decorative sparklines, projections, and smoothed indicators. Use
  /// [ChartInterpolation.linear] for observed prices, balances, net worth,
  /// and asset values where the line should not visually anticipate the next
  /// sample. Step lines can be added as a future interpolation mode.
  final ChartInterpolation interpolation;

  /// Backward-compatible shorthand for [interpolation].
  ///
  /// When supplied, this overrides [interpolation].
  final bool? curved;

  /// Bezier curve smoothness. 0 = straight segments, 1 = maximum smoothing.
  /// Default 0.28 prevents overshoot on volatile data.
  final double curveSmoothness;

  /// Draw a larger highlighted dot at the last data point of each series.
  /// Intended for hero / showcase charts only.
  final bool heroDots;

  /// Whether to render resting data-point dots. `null` keeps the historical
  /// auto-density behavior (dots only for short series). Set to `false` for
  /// dense analytical lines where touch crosshair feedback is enough.
  final bool? showDots;

  /// Whether to render the bottom X-axis labels in the resting chart.
  final bool showXAxis;

  /// Whether to render the left Y-axis labels in the resting chart.
  final bool showYAxis;

  /// Whether a compact X value label should appear near the crosshair while
  /// the user drags across the chart.
  final bool showTouchXAxisLabel;

  /// Sparkline mode: hide grid lines + axis tick labels + touch tooltip.
  /// Used for hero / cockpit micro-charts where the chart is decorative
  /// context, not an analytical surface. Overrides [showXAxis] /
  /// [TimeAxis.showGrid] / [ValueAxis.showGrid] / tooltip settings.
  final bool minimal;

  @override
  State<NwLineChart> createState() => _NwLineChartState();
}

enum ChartInterpolation { linear, curved }

class _NwLineChartState extends State<NwLineChart> {
  // Touch state is isolated in a ValueNotifier so that touch events
  // (pan/drag at 120fps) only rebuild the lightweight touch overlay,
  // NOT the entire chart (LineChart + axes + grid).
  final _touchNotifier = ValueNotifier<_TouchState?>(null);
  int _lastSpotIndex = -1;

  _PreparedLineData? _prepared;
  List<ChartSeries>? _preparedSource;
  bool? _preparedDownsample;
  int? _preparedDownsampleTarget;

  // Cached chart data — avoids rebuilding LineChartData on every touch event.
  _CachedChartData? _cachedChartData;
  _PreparedLineData? _cachedChartDataSource;
  ChartPalette? _cachedChartPalette;
  bool? _cachedHideAmounts;

  @override
  void dispose() {
    _touchNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final nonEmpty = widget.series.where((s) => s.points.isNotEmpty).toList();
    if (nonEmpty.isEmpty) {
      final ratio = widget.aspectRatio;
      const placeholder = EmptyChartPlaceholder();
      return ratio != null
          ? AspectRatio(aspectRatio: ratio, child: placeholder)
          : placeholder;
    }

    final palette = ChartPalette.of(context);
    final prepared = _prepare(nonEmpty);
    final processed = prepared.processed;
    final minX = widget.minX ?? prepared.minX;
    final maxX = widget.maxX ?? prepared.maxX;
    final minY = prepared.minY;
    final maxY = prepared.maxY;
    final yPad = prepared.yPad;
    final chartMinY = minY - yPad;
    final chartMaxY = maxY + yPad;
    final plotInsets = _plotInsets;
    final hideAmounts = AmountPrivacyScope.isHiddenOf(context);

    // Cache chart data — only rebuild when data/palette/privacy changes.
    // Touch events do NOT trigger a rebuild of this method, so the cached
    // data stays identical across touch frames.
    final cached = _cachedChartData;
    if (cached == null ||
        !identical(_cachedChartDataSource, prepared) ||
        _cachedChartPalette != palette ||
        _cachedHideAmounts != hideAmounts) {
      final lineBars = <LineChartBarData>[];
      for (var i = 0; i < processed.length; i++) {
        final s = processed[i];
        final color = resolveSeriesColor(
          context,
          intent: s.intent,
          ordinal: i,
          override: s.colorOverride,
        );
        lineBars.add(
          _buildBarData(
            context,
            s,
            prepared.spots[i],
            color,
            palette,
            i,
            processed.length,
          ),
        );
      }

      final showGrid =
          !widget.minimal && (widget.yAxis.showGrid || widget.xAxis.showGrid);
      final chartData = LineChartData(
        minX: minX,
        maxX: maxX,
        minY: chartMinY,
        maxY: chartMaxY,
        gridData: FlGridData(
          show: showGrid,
          drawHorizontalLine: showGrid && widget.yAxis.showGrid,
          drawVerticalLine: showGrid && widget.xAxis.showGrid,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: palette.gridLine, strokeWidth: AppStroke.hairline),
          getDrawingVerticalLine: (_) =>
              FlLine(color: palette.gridLine, strokeWidth: AppStroke.hairline),
        ),
        borderData: FlBorderData(show: false),
        titlesData: widget.minimal
            ? const FlTitlesData(show: false)
            : _buildTitles(palette, minX, maxX, minY, maxY, hideAmounts),
        lineBarsData: lineBars,
        lineTouchData: widget.minimal
            ? const LineTouchData(enabled: false)
            : _buildTouchData(context, palette, processed),
      );
      _cachedChartData = _CachedChartData(
        chartData: chartData,
        lineBars: lineBars,
        processed: processed,
      );
      _cachedChartDataSource = prepared;
      _cachedChartPalette = palette;
      _cachedHideAmounts = hideAmounts;
    }

    final chartDataObj = _cachedChartData!;

    // The main chart — wrapped in RepaintBoundary. Does NOT rebuild on
    // touch because we only update _touchNotifier (not setState).
    final chartWidget = RepaintBoundary(
      child: LineChart(chartDataObj.chartData),
    );

    // Touch overlay — rebuilt via ValueListenableBuilder only when
    // touch state changes. This is lightweight (crosshair + tooltip).
    final stack = Stack(
      children: [
        chartWidget,
        ValueListenableBuilder<_TouchState?>(
          valueListenable: _touchNotifier,
          builder: (context, touch, _) {
            if (touch == null) return const SizedBox.shrink();
            final spot = touch.spot;
            final spotIndex = touch.spotIndex;
            return Stack(
              children: [
                IgnorePointer(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      size: Size.infinite,
                      painter: _CrosshairPainter(
                        spot: spot,
                        lineBars: chartDataObj.lineBars,
                        minX: minX,
                        maxX: maxX,
                        minY: chartMinY,
                        maxY: chartMaxY,
                        plotInsets: plotInsets,
                        color: palette.axisLabel,
                        dotStrokeColor: palette.dotStroke,
                      ),
                    ),
                  ),
                ),
                if (spotIndex >= 0 &&
                    spotIndex < chartDataObj.processed.first.points.length)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: _ChartTooltip(
                        spotIndex: spotIndex,
                        processed: chartDataObj.processed,
                        xAxis: widget.xAxis,
                        yAxis: widget.yAxis,
                        touchStartPoint: touch.touchStartPoint,
                        hideAmounts: hideAmounts,
                      ),
                    ),
                  ),
                if (widget.showTouchXAxisLabel &&
                    spotIndex >= 0 &&
                    spotIndex < chartDataObj.processed.first.points.length)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: _TouchXAxisLabel(
                        spot: spot,
                        minX: minX,
                        maxX: maxX,
                        plotInsets: plotInsets,
                        label: widget.xAxis.formatPrecise(
                          chartDataObj.processed.first.points[spotIndex].x,
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
    final ratio = widget.aspectRatio;
    final chart = ratio != null
        ? AspectRatio(aspectRatio: ratio, child: stack)
        : stack;
    return Semantics(
      label: widget.semanticLabel,
      container: true,
      child: chart,
    );
  }
}
