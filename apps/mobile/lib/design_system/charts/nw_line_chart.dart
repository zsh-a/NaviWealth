import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/market_colors.dart';
import '../tokens/glass_tokens.dart';
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
class NwLineChart extends StatefulWidget {
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
    this.curveSmoothness = 0.28,
    this.heroDots = false,
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
  /// fill uses a gradient from 70% of the line color to transparent.
  /// For multi-series stacked fills use [NwAreaChart] with `stacked: true`.
  final bool filled;

  /// Bezier curve smoothness. 0 = straight segments, 1 = maximum smoothing.
  /// Default 0.28 prevents overshoot on volatile data.
  final double curveSmoothness;

  /// Draw a larger highlighted dot at the last data point of each series.
  /// Intended for hero / showcase charts only.
  final bool heroDots;

  @override
  State<NwLineChart> createState() => _NwLineChartState();
}

class _NwLineChartState extends State<NwLineChart> {
  double? _touchLocalX;
  ChartPoint? _touchStartPoint;
  int _lastSpotIndex = -1;

  @override
  Widget build(BuildContext context) {
    final nonEmpty =
        widget.series.where((s) => s.points.isNotEmpty).toList();
    if (nonEmpty.isEmpty) {
      return AspectRatio(
        aspectRatio: widget.aspectRatio,
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
            target: widget.downsampleTarget,
            enabled: widget.downsample,
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
      lineBars.add(
        _buildBarData(context, s, color, palette, i, processed.length),
      );
    }

    return Semantics(
      label: widget.semanticLabel,
      container: true,
      child: AspectRatio(
        aspectRatio: widget.aspectRatio,
        child: Stack(
          children: [
            LineChart(
              LineChartData(
                minX: minX,
                maxX: maxX,
                minY: minY - yPad,
                maxY: maxY + yPad,
                gridData: FlGridData(
                  show: widget.yAxis.showGrid || widget.xAxis.showGrid,
                  drawHorizontalLine: widget.yAxis.showGrid,
                  drawVerticalLine: widget.xAxis.showGrid,
                  getDrawingHorizontalLine: (_) =>
                      FlLine(color: palette.gridLine, strokeWidth: 1),
                  getDrawingVerticalLine: (_) =>
                      FlLine(color: palette.gridLine, strokeWidth: 1),
                ),
                borderData: FlBorderData(show: false),
                titlesData: _buildTitles(palette),
                lineBarsData: lineBars,
                lineTouchData: _buildTouchData(context, palette, processed),
              ),
            ),
            if (_touchLocalX != null) ...[
              IgnorePointer(
                child: CustomPaint(
                  size: Size.infinite,
                  painter: _CrosshairPainter(
                    touchX: _touchLocalX!,
                    lineBars: lineBars,
                    minX: minX,
                    maxX: maxX,
                    color: palette.axisLabel,
                  ),
                ),
              ),
              if (_touchedSpotIndex >= 0 &&
                  _touchedSpotIndex < processed.first.points.length)
                IgnorePointer(
                  child: _GlassTooltip(
                    spotIndex: _touchedSpotIndex,
                    processed: processed,
                    xAxis: widget.xAxis,
                    yAxis: widget.yAxis,
                    touchStartPoint: _touchStartPoint,
                  ),
                ),
            ],
          ],
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

    final effectiveColor =
        isComparison ? color.withValues(alpha: 0.6) : color;
    final effectiveDash =
        isComparison ? (dashArray ?? const [6, 4]) : (dashArray ?? (isProjection ? const [4, 4] : null));

    return LineChartBarData(
      spots: [for (final p in s.points) FlSpot(p.x, p.y)],
      isCurved: true,
      curveSmoothness: widget.curveSmoothness,
      color: effectiveColor,
      dashArray: effectiveDash,
      barWidth: s.strokeWidth ?? defaultStroke,
      dotData: FlDotData(
        show: s.points.length <= 60,
        getDotPainter: widget.heroDots && ordinal == 0
            ? (spot, percent, barData, index) {
                if (index != s.points.length - 1) {
                  return FlDotCirclePainter(
                    radius: 2.5,
                    color: effectiveColor,
                  );
                }
                return FlDotCirclePainter(
                  radius: 5,
                  color: effectiveColor,
                  strokeColor: effectiveColor.withValues(alpha: 0.25),
                  strokeWidth: 6,
                );
              }
            : (spot, percent, barData, index) => FlDotCirclePainter(
                radius: 2.5,
                color: effectiveColor,
              ),
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

  FlTitlesData _buildTitles(ChartPalette palette) {
    final labelStyle = TypographyTokens.numericCaption.copyWith(
      color: palette.axisLabel,
    );
    return FlTitlesData(
      topTitles:
          const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles:
          const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 24,
          getTitlesWidget: (value, meta) {
            return Padding(
              padding: const EdgeInsets.only(top: 4),
              child:
                  Text(widget.xAxis.formatTimestamp(value), style: labelStyle),
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
              child: Text(widget.yAxis.formatValue(value), style: labelStyle),
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
      touchTooltipData: LineTouchTooltipData(
        getTooltipColor: (_) => Colors.transparent,
        tooltipBorderRadius: BorderRadius.zero,
        tooltipPadding: EdgeInsets.zero,
        getTooltipItems: (_) => [],
      ),
      getTouchedSpotIndicator: (barData, spotIndexes) {
        return spotIndexes.map((index) {
          return TouchedSpotIndicatorData(
            const FlLine(
              color: Colors.transparent,
              strokeWidth: 0,
            ),
            FlDotData(
              show: true,
              getDotPainter: (spot, percent, bar, index) =>
                  FlDotCirclePainter(
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
        final localDx = event.localPosition?.dx;
        if (event is FlLongPressStart || event is FlPanStartEvent) {
          setState(() {
            _touchLocalX = localDx;
            _touchStartPoint = null;
            _lastSpotIndex = -1;
          });
          HapticFeedback.selectionClick();
          return;
        }
        if (event is FlLongPressMoveUpdate ||
            event is FlPanUpdateEvent) {
          setState(() {
            _touchLocalX = localDx;
          });
          _fireCrossingHaptic(response, processed);
          return;
        }
        if (event is FlLongPressEnd || event is FlPanEndEvent) {
          final dd = widget.drillDown;
          final touched = response?.lineBarSpots;
          if (touched != null &&
              touched.isNotEmpty &&
              dd is PointDrillDown) {
            final s = processed[touched.first.barIndex];
            final idx =
                touched.first.spotIndex.clamp(0, s.points.length - 1);
            dd.onTap(s.points[idx]);
          }
          setState(() {
            _touchLocalX = null;
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
            final idx =
                touched.first.spotIndex.clamp(0, s.points.length - 1);
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
            _touchLocalX = null;
            _touchStartPoint = null;
            _lastSpotIndex = -1;
          });
        }
      },
    );
  }

  void _fireCrossingHaptic(
    LineTouchResponse? response,
    List<ChartSeries> processed,
  ) {
    final touched = response?.lineBarSpots;
    if (touched == null || touched.isEmpty) return;
    final spotIndex = touched.first.spotIndex;
    if (spotIndex != _lastSpotIndex && _lastSpotIndex >= 0) {
      HapticFeedback.selectionClick();
    }
    _lastSpotIndex = spotIndex;
    final s = processed[touched.first.barIndex];
    final idx = spotIndex.clamp(0, s.points.length - 1);
    _touchStartPoint ??= s.points[idx];
  }

  int get _touchedSpotIndex => _lastSpotIndex;
}

// ---------------------------------------------------------------------------
// Crosshair painter — vertical dashed hairline + circle dot
// ---------------------------------------------------------------------------

class _CrosshairPainter extends CustomPainter {
  const _CrosshairPainter({
    required this.touchX,
    required this.lineBars,
    required this.minX,
    required this.maxX,
    required this.color,
  });

  final double touchX;
  final List<LineChartBarData> lineBars;
  final double minX;
  final double maxX;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (lineBars.isEmpty) return;
    final spots = lineBars.first.spots;
    if (spots.isEmpty) return;

    // Map touchX to data X, then find nearest spot.
    final dataX = minX + (touchX / size.width) * (maxX - minX);
    var nearest = spots.first;
    var nearestDist = (nearest.x - dataX).abs();
    for (final spot in spots.skip(1)) {
      final d = (spot.x - dataX).abs();
      if (d < nearestDist) {
        nearest = spot;
        nearestDist = d;
      }
    }

    // Map nearest data X back to pixel X.
    final pixelX =
        ((nearest.x - minX) / (maxX - minX)) * size.width;
    // Map Y: chart Y increases upward, pixel Y increases downward.
    final yRange = lineBars.expand((b) => b.spots).fold<double>(
          double.infinity,
          (m, s) => math.min(m, s.y),
        );
    final yMax = lineBars.expand((b) => b.spots).fold<double>(
          double.negativeInfinity,
          (m, s) => math.max(m, s.y),
        );
    final yPad = (yMax - yRange).abs() * 0.1 + 1;
    final chartMinY = yRange - yPad;
    final chartMaxY = yMax + yPad;
    final pixelY = size.height -
        ((nearest.y - chartMinY) / (chartMaxY - chartMinY)) * size.height;

    final paint = Paint()
      ..color = color.withValues(alpha: 0.35)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    // Vertical dashed hairline.
    _drawDashedLine(
      canvas,
      Offset(pixelX, 0),
      Offset(pixelX, size.height),
      paint,
      dashLength: 4,
      gapLength: 3,
    );

    // Horizontal dashed hairline at the touched value.
    _drawDashedLine(
      canvas,
      Offset(0, pixelY),
      Offset(size.width, pixelY),
      paint,
      dashLength: 4,
      gapLength: 3,
    );

    // Circle dot at the intersection.
    final dotPaint = Paint()
      ..color = lineBars.first.color ?? color
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(pixelX, pixelY), 4, dotPaint);
    final dotStroke = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(Offset(pixelX, pixelY), 4, dotStroke);
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
      final end = drawing ? math.min(pos + dashLength, length) : pos + gapLength;
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
  bool shouldRepaint(_CrosshairPainter old) => old.touchX != touchX;
}

// ---------------------------------------------------------------------------
// Glass Tooltip — tabular data + delta badges
// ---------------------------------------------------------------------------

class _GlassTooltip extends StatelessWidget {
  const _GlassTooltip({
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
    final safeIndex =
        spotIndex.clamp(0, processed.first.points.length - 1);
    final point = processed.first.points[safeIndex];
    final glass = GlassTokens.of(context);
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;

    return Positioned.fill(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Align(
          alignment: Alignment.topRight,
          child: ClipRRect(
            borderRadius:
                BorderRadius.circular(glass.borderRadius),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(
                sigmaX: glass.blurSigma,
                sigmaY: glass.blurSigma,
              ),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 200),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: glass.surfaceColor,
                  borderRadius:
                      BorderRadius.circular(glass.borderRadius),
                  border: Border.all(
                    color: glass.hairlineColor,
                    width: 1,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      xAxis.formatTimestamp(point.x),
                      style: TypographyTokens.numericCaption.copyWith(
                        color: onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                    const SizedBox(height: 4),
                    for (var i = 0; i < processed.length; i++)
                      _buildSeriesRow(
                        i,
                        processed[i],
                        safeIndex,
                        onSurface,
                      ),
                  ],
                ),
              ),
            ),
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
              style: TypographyTokens.numericCaption.copyWith(
                color: onSurface,
              ),
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

// ---------------------------------------------------------------------------
// Delta badge — colored chip showing +/– change
// ---------------------------------------------------------------------------

class _DeltaBadge extends StatelessWidget {
  const _DeltaBadge({required this.value, required this.yAxis});

  final double value;
  final ValueAxis yAxis;

  @override
  Widget build(BuildContext context) {
    final market = Theme.of(context).extension<MarketColors>();
    final positive = value >= 0;
    final color = market?.forDelta(value) ??
        (positive ? const Color(0xFF059669) : const Color(0xFFBE123C));
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
