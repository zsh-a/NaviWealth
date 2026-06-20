import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forui/forui.dart';

import '../theme/market_colors.dart';
import '../tokens/dimens_tokens.dart';
import '../tokens/typography_tokens.dart';
import '../widgets/amount_privacy_scope.dart';
import 'axes.dart';
import 'chart_palette.dart';
import 'chart_series.dart';
import 'downsample.dart';
import 'drilldown.dart';
import 'empty_chart_placeholder.dart';

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
    this.showXAxis = true,
    this.showTouchXAxisLabel = false,
    this.minimal = false,
  });

  final List<ChartSeries> series;
  final TimeAxis xAxis;
  final ValueAxis yAxis;
  final double? aspectRatio;
  final ChartDrillDown? drillDown;

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

  /// Whether to render the bottom X-axis labels in the resting chart.
  final bool showXAxis;

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
    final minX = prepared.minX;
    final maxX = prepared.maxX;
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

  LineChartBarData _buildBarData(
    BuildContext context,
    ChartSeries s,
    List<FlSpot> spots,
    Color color,
    ChartPalette palette,
    int ordinal,
    int totalSeries,
  ) {
    final dashArray = switch (s.emphasis) {
      SeriesEmphasis.solid => null,
      SeriesEmphasis.dashed => <int>[6, 4],
      SeriesEmphasis.dotted => <int>[2, 4],
    };
    final isProjection = s.intent == SeriesIntent.projection;
    final isPrimary = ordinal == 0 && totalSeries > 1;
    final isComparison = !isPrimary && totalSeries > 1;
    final defaultStroke = isProjection || s.intent == SeriesIntent.muted
        ? 1.5
        : 2.5;

    final effectiveColor = isComparison
        ? color.withValues(alpha: AppOpacity.prominent)
        : color;
    final effectiveDash = isComparison
        ? (dashArray ?? const [6, 4])
        : (dashArray ?? (isProjection ? const [4, 4] : null));

    final isCurved =
        widget.curved ?? widget.interpolation == ChartInterpolation.curved;
    return LineChartBarData(
      spots: spots,
      isCurved: isCurved,
      curveSmoothness: widget.curveSmoothness,
      color: effectiveColor,
      dashArray: effectiveDash,
      barWidth: s.strokeWidth ?? defaultStroke,
      dotData: FlDotData(
        show: s.points.length <= 60,
        getDotPainter: widget.heroDots && ordinal == 0
            ? (spot, percent, barData, index) {
                if (index != s.points.length - 1) {
                  return FlDotCirclePainter(radius: 2.5, color: effectiveColor);
                }
                return FlDotCirclePainter(
                  radius: 5,
                  color: effectiveColor,
                  strokeColor: effectiveColor.withValues(
                    alpha: AppOpacity.halo,
                  ),
                  strokeWidth: AppStroke.halo,
                );
              }
            : (spot, percent, barData, index) =>
                  FlDotCirclePainter(radius: 2.5, color: effectiveColor),
      ),
      belowBarData: widget.filled
          ? BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  color.withValues(
                    alpha: s.fillOpacity ?? _defaultFillTopAlpha(context),
                  ),
                  color.withValues(alpha: AppOpacity.transparent),
                ],
              ),
            )
          : BarAreaData(show: false),
    );
  }

  double _defaultFillTopAlpha(BuildContext context) {
    return context.theme.colors.brightness == Brightness.dark ? 0.18 : 0.12;
  }

  _PreparedLineData _prepare(List<ChartSeries> nonEmpty) {
    final cached = _prepared;
    if (cached != null &&
        identical(_preparedSource, widget.series) &&
        _preparedDownsample == widget.downsample &&
        _preparedDownsampleTarget == widget.downsampleTarget) {
      return cached;
    }

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
            target: widget.downsampleTarget,
            enabled: widget.downsample,
          ),
        ),
    ];

    var minX = double.infinity;
    var maxX = double.negativeInfinity;
    var minY = double.infinity;
    var maxY = double.negativeInfinity;
    final spots = <List<FlSpot>>[];
    for (final series in processed) {
      final seriesSpots = <FlSpot>[];
      for (final point in series.points) {
        if (point.x < minX) minX = point.x;
        if (point.x > maxX) maxX = point.x;
        if (point.y < minY) minY = point.y;
        if (point.y > maxY) maxY = point.y;
        seriesSpots.add(FlSpot(point.x, point.y));
      }
      spots.add(List.unmodifiable(seriesSpots));
    }
    final prepared = _PreparedLineData(
      processed: List.unmodifiable(processed),
      spots: List.unmodifiable(spots),
      minX: minX,
      maxX: maxX,
      minY: minY,
      maxY: maxY,
      yPad: (maxY - minY).abs() * 0.1 + 1,
    );
    _prepared = prepared;
    _preparedSource = widget.series;
    _preparedDownsample = widget.downsample;
    _preparedDownsampleTarget = widget.downsampleTarget;
    return prepared;
  }

  _ChartPlotInsets get _plotInsets => _ChartPlotInsets(
    left: widget.minimal ? 0 : _kLeftTitleReservedSize,
    bottom: !widget.minimal && widget.showXAxis ? _kBottomTitleReservedSize : 0,
  );

  FlTitlesData _buildTitles(
    ChartPalette palette,
    double minX,
    double maxX,
    double minY,
    double maxY,
    bool hideAmounts,
  ) {
    final labelStyle = TypographyTokens.numericCaption.copyWith(
      color: palette.axisLabel,
    );
    final xRange = (maxX - minX).abs();
    final yRange = (maxY - minY).abs();
    final xInterval = widget.xAxis.maxLabels > 0 && xRange > 0
        ? xRange / widget.xAxis.maxLabels
        : null;
    final yInterval = widget.yAxis.maxLabels > 0 && yRange > 0
        ? yRange / widget.yAxis.maxLabels
        : null;
    return FlTitlesData(
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: widget.showXAxis,
          reservedSize: widget.showXAxis ? _kBottomTitleReservedSize : 0,
          interval: xInterval,
          getTitlesWidget: (value, meta) {
            // Skip labels that would overlap on narrow charts.
            if (!shouldRenderAxisLabel(
              value: value,
              meta: meta,
              range: xRange,
              maxLabels: widget.xAxis.maxLabels,
            )) {
              return const SizedBox.shrink();
            }
            return Padding(
              padding: const EdgeInsets.only(top: AppSpacing.s4),
              child: Text(
                widget.xAxis.formatTimestamp(value),
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
          reservedSize: _kLeftTitleReservedSize,
          interval: yInterval,
          getTitlesWidget: (value, meta) {
            // Skip labels that would overlap on short charts.
            if (!shouldRenderAxisLabel(
              value: value,
              meta: meta,
              range: yRange,
              maxLabels: widget.yAxis.maxLabels,
            )) {
              return const SizedBox.shrink();
            }
            return Padding(
              padding: const EdgeInsets.only(right: AppSpacing.s4),
              child: Text(
                hideAmounts
                    ? AmountPrivacyScope.mask
                    : widget.yAxis.formatValue(value),
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

  LineTouchData _buildTouchData(
    BuildContext context,
    ChartPalette palette,
    List<ChartSeries> processed,
  ) {
    return LineTouchData(
      enabled: true,
      handleBuiltInTouches: false,
      touchSpotThreshold: double.infinity,
      touchTooltipData: LineTouchTooltipData(
        getTooltipColor: (_) => Colors.transparent,
        tooltipBorderRadius: BorderRadius.zero,
        tooltipPadding: EdgeInsets.zero,
        getTooltipItems: (spots) =>
            List<LineTooltipItem?>.filled(spots.length, null),
      ),
      getTouchedSpotIndicator: (barData, spotIndexes) {
        return spotIndexes.map((index) {
          return TouchedSpotIndicatorData(
            const FlLine(
              color: Colors.transparent,
              strokeWidth: AppStroke.none,
            ),
            FlDotData(
              show: true,
              getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
                radius: 4,
                color: bar.color ?? Colors.transparent,
                strokeColor: palette.dotStroke,
                strokeWidth: AppStroke.medium,
              ),
            ),
          );
        }).toList();
      },
      // Touch callback updates ValueNotifier instead of calling setState,
      // so the main chart widget tree does NOT rebuild on touch events.
      touchCallback: (event, response) {
        if (event is FlLongPressStart || event is FlPanStartEvent) {
          final touched = _primaryTouchedSpot(response);
          _lastSpotIndex = -1;
          _touchNotifier.value = touched == null
              ? null
              : _TouchState(
                  spot: touched,
                  spotIndex: -1,
                  touchStartPoint: null,
                );
          _fireCrossingHaptic(response, processed);
          HapticFeedback.selectionClick();
          return;
        }
        if (event is FlLongPressMoveUpdate || event is FlPanUpdateEvent) {
          final touched = _primaryTouchedSpot(response);
          if (touched == null) _lastSpotIndex = -1;
          _fireCrossingHaptic(response, processed);
          return;
        }
        if (event is FlLongPressEnd || event is FlPanEndEvent) {
          final dd = widget.drillDown;
          final touched = response?.lineBarSpots;
          if (touched != null && touched.isNotEmpty && dd is PointDrillDown) {
            final s = processed[touched.first.barIndex];
            final idx = touched.first.spotIndex.clamp(0, s.points.length - 1);
            dd.onTap(s.points[idx]);
          }
          _lastSpotIndex = -1;
          _touchNotifier.value = null;
          return;
        }
        if (event is FlTapUpEvent) {
          final dd = widget.drillDown;
          final touched = response?.lineBarSpots;
          if (touched != null && touched.isNotEmpty) {
            final s = processed[touched.first.barIndex];
            final idx = touched.first.spotIndex.clamp(0, s.points.length - 1);
            final point = s.points[idx];
            if (dd is PointDrillDown) {
              if (dd.haptic) HapticFeedback.selectionClick();
              dd.onTap(point);
            } else if (dd is RangeDrillDown) {
              dd.onRange(
                ChartRangeSelection(
                  start: point.x,
                  end: point.x,
                  points: [point],
                ),
              );
            }
          }
          _lastSpotIndex = -1;
          _touchNotifier.value = null;
        }
      },
    );
  }

  TouchLineBarSpot? _primaryTouchedSpot(LineTouchResponse? response) {
    final touched = response?.lineBarSpots;
    if (touched == null || touched.isEmpty) return null;
    return touched.firstWhere(
      (spot) => spot.barIndex == 0,
      orElse: () => touched.first,
    );
  }

  void _fireCrossingHaptic(
    LineTouchResponse? response,
    List<ChartSeries> processed,
  ) {
    final touched = _primaryTouchedSpot(response);
    if (touched == null) return;
    final spotIndex = touched.spotIndex;
    if (spotIndex != _lastSpotIndex && _lastSpotIndex >= 0) {
      HapticFeedback.selectionClick();
    }
    _lastSpotIndex = spotIndex;
    final s = processed[touched.barIndex];
    final idx = spotIndex.clamp(0, s.points.length - 1);
    final prev = _touchNotifier.value;
    _touchNotifier.value = _TouchState(
      spot: touched,
      spotIndex: spotIndex,
      touchStartPoint: prev?.touchStartPoint ?? s.points[idx],
    );
  }
}

/// Immutable touch state — passed to ValueListenableBuilder so the
/// touch overlay rebuilds independently of the main chart.
class _TouchState {
  const _TouchState({
    required this.spot,
    required this.spotIndex,
    required this.touchStartPoint,
  });

  final FlSpot spot;
  final int spotIndex;
  final ChartPoint? touchStartPoint;
}

/// Cached chart data — avoids rebuilding LineChartData on every touch event.
class _CachedChartData {
  const _CachedChartData({
    required this.chartData,
    required this.lineBars,
    required this.processed,
  });

  final LineChartData chartData;
  final List<LineChartBarData> lineBars;
  final List<ChartSeries> processed;
}

class _PreparedLineData {
  const _PreparedLineData({
    required this.processed,
    required this.spots,
    required this.minX,
    required this.maxX,
    required this.minY,
    required this.maxY,
    required this.yPad,
  });

  final List<ChartSeries> processed;
  final List<List<FlSpot>> spots;
  final double minX;
  final double maxX;
  final double minY;
  final double maxY;
  final double yPad;
}

class _ChartPlotInsets {
  const _ChartPlotInsets({this.left = 0, this.bottom = 0});

  final double left;
  final double bottom;

  Rect resolve(Size size) =>
      Rect.fromLTRB(left, 0, size.width, math.max(0, size.height - bottom));

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _ChartPlotInsets && left == other.left && bottom == other.bottom;

  @override
  int get hashCode => Object.hash(left, bottom);
}

// ---------------------------------------------------------------------------
// Crosshair painter — vertical dashed hairline + circle dot
// ---------------------------------------------------------------------------

class _CrosshairPainter extends CustomPainter {
  _CrosshairPainter({
    required this.spot,
    required this.lineBars,
    required this.minX,
    required this.maxX,
    required this.minY,
    required this.maxY,
    required this.plotInsets,
    required this.color,
    required this.dotStrokeColor,
  });

  final FlSpot spot;
  final List<LineChartBarData> lineBars;
  final double minX;
  final double maxX;
  final double minY;
  final double maxY;
  final _ChartPlotInsets plotInsets;
  final Color color;
  final Color dotStrokeColor;

  // Cached Paint objects — reused across frames.
  late final _hairlinePaint = Paint()
    ..color = color.withValues(alpha: AppOpacity.muted)
    ..strokeWidth = AppStroke.hairline
    ..style = PaintingStyle.stroke;
  late final _dotFillPaint = Paint()..style = PaintingStyle.fill;
  late final _dotStrokePaint = Paint()
    ..color = dotStrokeColor
    ..style = PaintingStyle.stroke
    ..strokeWidth = AppStroke.medium;

  @override
  void paint(Canvas canvas, Size size) {
    if (lineBars.isEmpty) return;
    final plot = plotInsets.resolve(size);
    if (plot.width <= 0 || plot.height <= 0) return;

    final pixelX = _spotPixelX(spot.x, plot, minX, maxX);
    final pixelY = _spotPixelY(spot.y, plot, minY, maxY);

    // Vertical dashed hairline.
    _drawDashedLine(
      canvas,
      Offset(pixelX, plot.top),
      Offset(pixelX, plot.bottom),
      _hairlinePaint,
      dashLength: 4,
      gapLength: 3,
    );

    // Horizontal dashed hairline at the touched value.
    _drawDashedLine(
      canvas,
      Offset(plot.left, pixelY),
      Offset(plot.right, pixelY),
      _hairlinePaint,
      dashLength: 4,
      gapLength: 3,
    );

    // Circle dot at the intersection.
    _dotFillPaint.color = lineBars.first.color ?? color;
    canvas.drawCircle(Offset(pixelX, pixelY), 4, _dotFillPaint);
    canvas.drawCircle(Offset(pixelX, pixelY), 4, _dotStrokePaint);
  }

  void _drawDashedLine(
    Canvas canvas,
    Offset from,
    Offset to,
    Paint paint, {
    required double dashLength,
    required double gapLength,
  }) {
    final dx = to.dx - from.dx;
    final dy = to.dy - from.dy;
    final length = math.sqrt(dx * dx + dy * dy);
    final ux = dx / length;
    final uy = dy / length;
    var pos = 0.0;
    var drawing = true;
    while (pos < length) {
      final end = drawing
          ? math.min(pos + dashLength, length)
          : pos + gapLength;
      if (drawing) {
        canvas.drawLine(
          Offset(from.dx + ux * pos, from.dy + uy * pos),
          Offset(from.dx + ux * end, from.dy + uy * end),
          paint,
        );
      }
      pos = end;
      drawing = !drawing;
    }
  }

  @override
  bool shouldRepaint(_CrosshairPainter old) =>
      old.spot != spot ||
      old.minX != minX ||
      old.maxX != maxX ||
      old.minY != minY ||
      old.maxY != maxY ||
      old.plotInsets != plotInsets ||
      old.dotStrokeColor != dotStrokeColor;
}

// ---------------------------------------------------------------------------
// Tooltip — tabular data + delta badges
// ---------------------------------------------------------------------------

class _ChartTooltip extends StatelessWidget {
  const _ChartTooltip({
    required this.spotIndex,
    required this.processed,
    required this.xAxis,
    required this.yAxis,
    required this.touchStartPoint,
    required this.hideAmounts,
  });

  final int spotIndex;
  final List<ChartSeries> processed;
  final TimeAxis xAxis;
  final ValueAxis yAxis;
  final ChartPoint? touchStartPoint;
  final bool hideAmounts;

  @override
  Widget build(BuildContext context) {
    if (processed.isEmpty || processed.first.points.isEmpty) {
      return const SizedBox.shrink();
    }
    final safeIndex = spotIndex.clamp(0, processed.first.points.length - 1);
    final point = processed.first.points[safeIndex];
    final onSurface = context.theme.colors.foreground;

    // Tooltips are small, transient, and frequently re-positioned as the
    // user drags the spot indicator. Per-frame BackdropFilter resampling
    // is wasted work on a panel that rebuilds whenever the spot index
    // changes. Use a near-opaque themed surface — keeps the panel
    // legible over busy chart lines without GPU readback.
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: Align(
        alignment: Alignment.topRight,
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Cap the tooltip at half of the chart's available width so it
            // never dominates narrow phones (320dp → ≤160px panel) while
            // still allowing the design's 200px ceiling on tablets/desktops.
            final maxWidth = math.min(200.0, constraints.maxWidth * 0.5);
            return Container(
              constraints: BoxConstraints(maxWidth: maxWidth),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s8 + AppSpacing.s2, // 10
                vertical: AppSpacing.s8,
              ),
              decoration: BoxDecoration(
                color: context.theme.colors.muted.withValues(
                  alpha: AppOpacity.solidSurface,
                ),
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(
                  color: context.theme.colors.border.withValues(
                    alpha: AppOpacity.scrim,
                  ),
                  width: AppStroke.hairline,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    xAxis.formatPrecise(point.x),
                    style: TypographyTokens.numericCaption.copyWith(
                      color: onSurface.withValues(alpha: AppOpacity.prominent),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s4),
                  for (var i = 0; i < processed.length; i++)
                    _buildSeriesRow(
                      i,
                      processed[i],
                      safeIndex,
                      onSurface,
                      hideAmounts,
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSeriesRow(
    int seriesIndex,
    ChartSeries s,
    int safeIndex,
    Color onSurface,
    bool hideAmounts,
  ) {
    if (safeIndex >= s.points.length) return const SizedBox.shrink();
    final p = s.points[safeIndex];
    final valueStr = hideAmounts
        ? AmountPrivacyScope.mask
        : yAxis.formatValue(p.y);
    final delta = touchStartPoint != null ? p.y - touchStartPoint!.y : 0.0;

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.accentBar),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${s.name}  $valueStr',
              style: TypographyTokens.numericCaption.copyWith(color: onSurface),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (touchStartPoint != null) ...[
            const SizedBox(width: AppSpacing.s6),
            _DeltaBadge(value: delta, yAxis: yAxis, hideAmounts: hideAmounts),
          ],
        ],
      ),
    );
  }
}

class _TouchXAxisLabel extends StatelessWidget {
  const _TouchXAxisLabel({
    required this.spot,
    required this.minX,
    required this.maxX,
    required this.plotInsets,
    required this.label,
  });

  final FlSpot spot;
  final double minX;
  final double maxX;
  final _ChartPlotInsets plotInsets;
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = ChartPalette.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        const width = 88.0;
        final maxLeft = (constraints.maxWidth - width)
            .clamp(0.0, double.infinity)
            .toDouble();
        final plot = plotInsets.resolve(
          Size(constraints.maxWidth, constraints.maxHeight),
        );
        final centerX = _spotPixelX(spot.x, plot, minX, maxX);
        final left = (centerX - width / 2).clamp(0.0, maxLeft).toDouble();
        return Stack(
          children: [
            Positioned(
              left: left,
              bottom: plotInsets.bottom + AppSpacing.s2,
              width: width,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: palette.tooltipBackground,
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.s6,
                    vertical: AppSpacing.accentBar,
                  ),
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TypographyTokens.numericCaption.copyWith(
                      color: palette.tooltipForeground,
                      fontSize: 10,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

double _spotPixelX(double x, Rect plot, double minX, double maxX) {
  final range = maxX - minX;
  if (range == 0) return plot.left;
  return plot.left + ((x - minX) / range) * plot.width;
}

double _spotPixelY(double y, Rect plot, double minY, double maxY) {
  final range = maxY - minY;
  if (range == 0) return plot.bottom;
  return plot.bottom - ((y - minY) / range) * plot.height;
}

// ---------------------------------------------------------------------------
// Delta badge — colored chip showing +/– change
// ---------------------------------------------------------------------------

class _DeltaBadge extends StatelessWidget {
  const _DeltaBadge({
    required this.value,
    required this.yAxis,
    required this.hideAmounts,
  });

  final double value;
  final ValueAxis yAxis;
  final bool hideAmounts;

  @override
  Widget build(BuildContext context) {
    final market = MarketColors.of(context);
    final positive = value >= 0;
    final color = market.forDelta(value);
    final bg = color.withValues(alpha: AppOpacity.accentContainer);
    final sign = positive ? '+' : '';
    final label = hideAmounts
        ? AmountPrivacyScope.mask
        : '$sign${yAxis.formatValue(value)}';

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s6,
        vertical: AppSpacing.hairline,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Text(
        label,
        style: TypographyTokens.numericCaption.copyWith(
          color: color,
          fontSize: 10,
        ),
      ),
    );
  }
}
