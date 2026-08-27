part of 'nw_line_chart.dart';

extension _NwLineChartData on _NwLineChartState {
  _PreparedLineData _prepare(List<ChartSeries> nonEmpty) {
    final cached = _prepared;
    if (cached != null &&
        _sameSeriesData(_preparedSource, widget.series) &&
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
      yPad: _adaptiveYPadding(minY, maxY),
    );
    _prepared = prepared;
    _preparedSource = widget.series;
    _preparedDownsample = widget.downsample;
    _preparedDownsampleTarget = widget.downsampleTarget;
    return prepared;
  }

  /// Keep the visible Y range proportional to the observed values.
  ///
  /// A fixed padding value makes low-magnitude series such as FX rates look
  /// flat: the difference between 7.18 and 7.20 is only 0.02, so adding 1
  /// on both sides wastes almost the entire vertical scale. A relative
  /// fallback is only needed when every sample has the same value.
  double _adaptiveYPadding(double minY, double maxY) {
    final span = (maxY - minY).abs();
    if (span > 0) return span * 0.1;

    final magnitude = math.max(minY.abs(), maxY.abs());
    return math.max(magnitude * 0.01, 0.000001);
  }

  bool _sameSeriesData(List<ChartSeries>? previous, List<ChartSeries> next) {
    if (previous == null || previous.length != next.length) return false;
    if (identical(previous, next)) return true;
    for (var seriesIndex = 0; seriesIndex < next.length; seriesIndex++) {
      final left = previous[seriesIndex];
      final right = next[seriesIndex];
      if (left.name != right.name ||
          left.intent != right.intent ||
          left.emphasis != right.emphasis ||
          left.colorOverride != right.colorOverride ||
          left.fillOpacity != right.fillOpacity ||
          left.strokeWidth != right.strokeWidth ||
          left.points.length != right.points.length) {
        return false;
      }
      if (identical(left.points, right.points)) continue;
      for (var pointIndex = 0; pointIndex < right.points.length; pointIndex++) {
        final leftPoint = left.points[pointIndex];
        final rightPoint = right.points[pointIndex];
        if (leftPoint.x != rightPoint.x ||
            leftPoint.y != rightPoint.y ||
            leftPoint.meta != rightPoint.meta) {
          return false;
        }
      }
    }
    return true;
  }
}
