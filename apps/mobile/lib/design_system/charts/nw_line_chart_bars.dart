part of 'nw_line_chart.dart';

extension _NwLineChartBars on _NwLineChartState {
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
      // Resting charts stay line-only by default — dots read as noisy on
      // wealth / portfolio trends. Opt in with [NwLineChart.showDots] /
      // [NwLineChart.heroDots] for sparklines that need an end-cap.
      dotData: FlDotData(
        show: widget.showDots == true || widget.heroDots,
        getDotPainter: widget.heroDots && ordinal == 0
            ? (spot, percent, barData, index) {
                if (index != s.points.length - 1) {
                  return FlDotCirclePainter(
                    radius: 0,
                    color: Colors.transparent,
                  );
                }
                return FlDotCirclePainter(
                  radius: 4,
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
}
