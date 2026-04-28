import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../data/physical_asset.dart';

/// Line chart of valuation history.
///
/// Manual / purchase points always show as filled dots; the projected
/// curve (vehicle auto-depreciation) is rendered as a translucent fill so
/// users can tell at a glance which segments came from the database vs the
/// depreciation model.
class ValuationTrendChart extends StatelessWidget {
  const ValuationTrendChart({
    super.key,
    required this.points,
    required this.projection,
    required this.currency,
  });

  final List<ValuationPoint> points;
  final List<ValuationPoint> projection;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (points.isEmpty && projection.isEmpty) {
      return const SizedBox.shrink();
    }
    final manualSpots = _toSpots(points);
    final projectionSpots = _toSpots(projection);
    final all = [...points, ...projection];
    final minX = all
        .map((p) => p.asOf.millisecondsSinceEpoch.toDouble())
        .reduce((a, b) => a < b ? a : b);
    final maxX = all
        .map((p) => p.asOf.millisecondsSinceEpoch.toDouble())
        .reduce((a, b) => a > b ? a : b);
    final values = all.map((p) => p.value.toDouble()).toList();
    final minY = values.reduce((a, b) => a < b ? a : b);
    final maxY = values.reduce((a, b) => a > b ? a : b);
    final yPad = (maxY - minY).abs() * 0.1 + 1;
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: LineChart(
        LineChartData(
          minX: minX,
          maxX: maxX,
          minY: (minY - yPad).clamp(0, double.infinity),
          maxY: maxY + yPad,
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          titlesData: const FlTitlesData(show: false),
          lineBarsData: [
            if (projectionSpots.length >= 2)
              LineChartBarData(
                spots: projectionSpots,
                isCurved: false,
                dashArray: [4, 4],
                color: theme.colorScheme.tertiary,
                barWidth: 1.5,
                dotData: const FlDotData(show: false),
              ),
            if (manualSpots.isNotEmpty)
              LineChartBarData(
                spots: manualSpots,
                isCurved: false,
                color: theme.colorScheme.primary,
                barWidth: 2.5,
                dotData: const FlDotData(show: true),
                belowBarData: BarAreaData(
                  show: true,
                  color: theme.colorScheme.primary.withValues(alpha: 0.08),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static List<FlSpot> _toSpots(List<ValuationPoint> pts) {
    final sorted = [...pts]..sort((a, b) => a.asOf.compareTo(b.asOf));
    return sorted
        .map(
          (p) => FlSpot(
            p.asOf.millisecondsSinceEpoch.toDouble(),
            p.value.toDouble(),
          ),
        )
        .toList();
  }
}
