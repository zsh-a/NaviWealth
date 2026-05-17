import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forui/forui.dart';

import '../theme/market_colors.dart';
import '../tokens/typography_tokens.dart';
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
  ChartPoint? _touchStartPoint;
  int _lastSpotIndex = -1;
  FlSpot? _touchedSpot;
  _PreparedLineData? _prepared;
  List<ChartSeries>? _preparedSource;
  bool? _preparedDownsample;
  int? _preparedDownsampleTarget;

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
    final stack = Stack(
      children: [
        RepaintBoundary(
          child: LineChart(
            LineChartData(
              minX: minX,
              maxX: maxX,
              minY: chartMinY,
              maxY: chartMaxY,
              gridData: FlGridData(
                show: showGrid,
                drawHorizontalLine: showGrid && widget.yAxis.showGrid,
                drawVerticalLine: showGrid && widget.xAxis.showGrid,
                getDrawingHorizontalLine: (_) =>
                    FlLine(color: palette.gridLine, strokeWidth: 1),
                getDrawingVerticalLine: (_) =>
                    FlLine(color: palette.gridLine, strokeWidth: 1),
              ),
              borderData: FlBorderData(show: false),
              titlesData: widget.minimal
                  ? const FlTitlesData(show: false)
                  : _buildTitles(palette, minX, maxX, minY, maxY),
              lineBarsData: lineBars,
              lineTouchData: widget.minimal
                  ? const LineTouchData(enabled: false)
                  : _buildTouchData(context, palette, processed),
            ),
          ),
        ),
        if (_touchedSpot != null) ...[
          IgnorePointer(
            child: RepaintBoundary(
              child: CustomPaint(
                size: Size.infinite,
                painter: _CrosshairPainter(
                  spot: _touchedSpot!,
                  lineBars: lineBars,
                  minX: minX,
                  maxX: maxX,
                  minY: chartMinY,
                  maxY: chartMaxY,
                  plotInsets: plotInsets,
                  color: palette.axisLabel,
                ),
              ),
            ),
          ),
          if (_touchedSpotIndex >= 0 &&
              _touchedSpotIndex < processed.first.points.length)
            Positioned.fill(
              child: IgnorePointer(
                child: _ChartTooltip(
                  spotIndex: _touchedSpotIndex,
                  processed: processed,
                  xAxis: widget.xAxis,
                  yAxis: widget.yAxis,
                  touchStartPoint: _touchStartPoint,
                ),
              ),
            ),
          if (widget.showTouchXAxisLabel &&
              _touchedSpotIndex >= 0 &&
              _touchedSpotIndex < processed.first.points.length)
            Positioned.fill(
              child: IgnorePointer(
                child: _TouchXAxisLabel(
                  spot: _touchedSpot!,
                  minX: minX,
                  maxX: maxX,
                  plotInsets: plotInsets,
                  label: widget.xAxis.formatPrecise(
                    processed.first.points[_touchedSpotIndex].x,
                  ),
                ),
              ),
            ),
        ],
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

    final effectiveColor = isComparison ? color.withValues(alpha: 0.6) : color;
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
                  strokeColor: effectiveColor.withValues(alpha: 0.25),
                  strokeWidth: 6,
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
                  color.withValues(alpha: 0),
                ],
              ),
            )
          : BarAreaData(show: false),
    );
  }

  double _defaultFillTopAlpha(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark ? 0.18 : 0.12;
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
            return Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                widget.xAxis.formatTimestamp(value),
                style: labelStyle,
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
            // Single line, right-aligned — a wrapping currency/negative
            // label used to break into a stray "-" + "¥0.50" stack and
            // collide with anything below the chart.
            return Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Text(
                widget.yAxis.formatValue(value),
                style: labelStyle,
                maxLines: 1,
                softWrap: false,
                textAlign: TextAlign.right,
                overflow: TextOverflow.visible,
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
            const FlLine(color: Colors.transparent, strokeWidth: 0),
            FlDotData(
              show: true,
              getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
                radius: 4,
                color: bar.color ?? Colors.transparent,
                strokeColor: Colors.white,
                strokeWidth: 1.5,
              ),
            ),
          );
        }).toList();
      },
      touchCallback: (event, response) {
        if (event is FlLongPressStart || event is FlPanStartEvent) {
          final touched = _primaryTouchedSpot(response);
          setState(() {
            _touchedSpot = touched;
            _touchStartPoint = null;
            _lastSpotIndex = -1;
          });
          _fireCrossingHaptic(response, processed);
          HapticFeedback.selectionClick();
          return;
        }
        if (event is FlLongPressMoveUpdate || event is FlPanUpdateEvent) {
          final touched = _primaryTouchedSpot(response);
          setState(() {
            _touchedSpot = touched;
            if (touched == null) _lastSpotIndex = -1;
          });
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
          setState(() {
            _touchedSpot = null;
            _touchStartPoint = null;
            _lastSpotIndex = -1;
          });
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
          setState(() {
            _touchedSpot = null;
            _touchStartPoint = null;
            _lastSpotIndex = -1;
          });
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
    _touchedSpot = touched;
    final s = processed[touched.barIndex];
    final idx = spotIndex.clamp(0, s.points.length - 1);
    _touchStartPoint ??= s.points[idx];
  }

  int get _touchedSpotIndex => _lastSpotIndex;
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
  });

  final FlSpot spot;
  final List<LineChartBarData> lineBars;
  final double minX;
  final double maxX;
  final double minY;
  final double maxY;
  final _ChartPlotInsets plotInsets;
  final Color color;

  // Cached Paint objects — reused across frames.
  late final _hairlinePaint = Paint()
    ..color = color.withValues(alpha: 0.35)
    ..strokeWidth = 1
    ..style = PaintingStyle.stroke;
  late final _dotFillPaint = Paint()..style = PaintingStyle.fill;
  static final _dotStrokePaint = Paint()
    ..color = Colors.white
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5;

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
      old.plotInsets != plotInsets;
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
  });

  final int spotIndex;
  final List<ChartSeries> processed;
  final TimeAxis xAxis;
  final ValueAxis yAxis;
  final ChartPoint? touchStartPoint;

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
    // is wasted work on a 200-px panel that rebuilds whenever the spot
    // index changes. Use a near-opaque themed surface — keeps the panel
    // legible over busy chart lines without GPU readback.
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Align(
        alignment: Alignment.topRight,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 200),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: context.theme.colors.muted.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: context.theme.colors.border.withValues(alpha: 0.5),
              width: 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                xAxis.formatPrecise(point.x),
                style: TypographyTokens.numericCaption.copyWith(
                  color: onSurface.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 4),
              for (var i = 0; i < processed.length; i++)
                _buildSeriesRow(i, processed[i], safeIndex, onSurface),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSeriesRow(
    int seriesIndex,
    ChartSeries s,
    int safeIndex,
    Color onSurface,
  ) {
    if (safeIndex >= s.points.length) return const SizedBox.shrink();
    final p = s.points[safeIndex];
    final valueStr = yAxis.formatValue(p.y);
    final delta = touchStartPoint != null ? p.y - touchStartPoint!.y : 0.0;

    return Padding(
      padding: const EdgeInsets.only(top: 3),
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
            const SizedBox(width: 6),
            _DeltaBadge(value: delta, yAxis: yAxis),
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
              bottom: plotInsets.bottom + 2,
              width: width,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: palette.tooltipBackground,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 3,
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
  const _DeltaBadge({required this.value, required this.yAxis});

  final double value;
  final ValueAxis yAxis;

  @override
  Widget build(BuildContext context) {
    final market = MarketColors.of(context);
    final positive = value >= 0;
    final color = market.forDelta(value);
    final bg = color.withValues(alpha: 0.15);
    final sign = positive ? '+' : '';
    final label = '$sign${yAxis.formatValue(value)}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
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
