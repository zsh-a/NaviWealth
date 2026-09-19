part of 'nw_line_chart.dart';

extension _NwLineChartAxes on _NwLineChartState {
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
        ? xRange / math.max(1, widget.xAxis.maxLabels - 1)
        : null;
    final yInterval = widget.yAxis.maxLabels > 0 && yRange > 0
        ? yRange / math.max(1, widget.yAxis.maxLabels - 1)
        : null;
    final yLabel = widget.yAxis.tickFormatter(
      min: minY,
      max: maxY,
      interval: yInterval ?? 1,
    );
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
              formatLabel: widget.xAxis.formatTimestamp,
            )) {
              return const SizedBox.shrink();
            }
            return SideTitleWidget(
              meta: meta,
              fitInside: SideTitleFitInsideData.fromTitleMeta(meta),
              space: AppSpacing.s4,
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
          showTitles: widget.showYAxis && !hideAmounts,
          reservedSize: widget.showYAxis && !hideAmounts
              ? widget.yAxis.reservedWidth(
                  context,
                  labelStyle,
                  min: minY,
                  max: maxY,
                  interval: yInterval ?? 1,
                )
              : 0,
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
                yLabel(value),
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
}
