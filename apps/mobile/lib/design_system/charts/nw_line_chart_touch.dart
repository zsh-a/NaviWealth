part of 'nw_line_chart.dart';

extension _NwLineChartInteraction on _NwLineChartState {
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
          _emitScrub(response, processed);
          _fireCrossingHaptic(response, processed);
          HapticFeedback.selectionClick();
          return;
        }
        if (event is FlLongPressMoveUpdate || event is FlPanUpdateEvent) {
          final touched = _primaryTouchedSpot(response);
          if (touched == null) _lastSpotIndex = -1;
          _emitScrub(response, processed);
          _fireCrossingHaptic(response, processed);
          return;
        }
        if (event is FlLongPressEnd ||
            event is FlPanEndEvent ||
            event is FlPanCancelEvent) {
          final dd = widget.drillDown;
          final touched = response?.lineBarSpots;
          if (event is! FlPanCancelEvent &&
              touched != null &&
              touched.isNotEmpty &&
              dd is PointDrillDown) {
            final s = processed[touched.first.barIndex];
            final idx = touched.first.spotIndex.clamp(0, s.points.length - 1);
            dd.onTap(s.points[idx]);
          }
          _lastSpotIndex = -1;
          _touchNotifier.value = null;
          widget.onScrub?.call(null);
          widget.onScrubChanged?.call(null);
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
          widget.onScrub?.call(null);
          widget.onScrubChanged?.call(null);
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

  void _emitScrub(LineTouchResponse? response, List<ChartSeries> processed) {
    final onScrub = widget.onScrub;
    final onScrubChanged = widget.onScrubChanged;
    if (onScrub == null && onScrubChanged == null) return;
    final touched = _primaryTouchedSpot(response);
    if (touched == null) {
      onScrub?.call(null);
      onScrubChanged?.call(null);
      return;
    }
    final s = processed[touched.barIndex];
    if (s.points.isEmpty) {
      onScrub?.call(null);
      onScrubChanged?.call(null);
      return;
    }
    final idx = touched.spotIndex.clamp(0, s.points.length - 1);
    final point = s.points[idx];
    onScrub?.call(point);
    onScrubChanged?.call(
      NwScrubState(
        point: point,
        seriesName: s.name,
        seriesIndex: touched.barIndex,
      ),
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
                      context,
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
    BuildContext context,
    int seriesIndex,
    ChartSeries s,
    int safeIndex,
    Color onSurface,
    bool hideAmounts,
  ) {
    if (safeIndex >= s.points.length) return const SizedBox.shrink();
    final p = s.points[safeIndex];
    final delta = touchStartPoint != null ? p.y - touchStartPoint!.y : 0.0;

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.accentBar),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    s.name,
                    style: TypographyTokens.numericCaption.copyWith(
                      color: onSurface,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: AppSpacing.s6),
                if (hideAmounts)
                  AmountPrivacyPlaceholder(
                    density: AmountPrivacyPlaceholderDensity.compact,
                    style: TypographyTokens.numericCaption,
                  )
                else
                  Text(
                    yAxis.formatValue(p.y),
                    style: TypographyTokens.numericCaption.copyWith(
                      color: onSurface,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
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
                  borderRadius: BorderRadius.circular(AppRadius.sm),
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
                    style: TypographyTokens.chartCaption.copyWith(
                      color: palette.tooltipForeground,
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
    final market = context.appTheme.market;
    if (hideAmounts) {
      final colors = context.theme.colors;
      return Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s6,
          vertical: AppSpacing.s4,
        ),
        decoration: BoxDecoration(
          color: colors.muted.withValues(alpha: AppOpacity.subtle),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: AmountPrivacyPlaceholder(
          density: AmountPrivacyPlaceholderDensity.compact,
          style: TypographyTokens.chartCaption,
        ),
      );
    }
    final positive = value >= 0;
    final color = market.roleForDelta(value).fg;
    final bg = color.withValues(alpha: AppOpacity.accentContainer);
    final sign = positive ? '+' : '';
    final label = '$sign${yAxis.formatValue(value)}';

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s6,
        vertical: AppSpacing.hairline,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        label,
        style: TypographyTokens.chartCaption.copyWith(color: color),
      ),
    );
  }
}
