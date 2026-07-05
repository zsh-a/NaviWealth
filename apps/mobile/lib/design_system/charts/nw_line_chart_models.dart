part of 'nw_line_chart.dart';

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
