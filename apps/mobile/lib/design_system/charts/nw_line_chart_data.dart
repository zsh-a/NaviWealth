part of 'nw_line_chart.dart';

extension _NwLineChartData on _NwLineChartState {
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
}
