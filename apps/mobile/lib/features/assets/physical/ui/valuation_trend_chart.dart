import 'package:flutter/widgets.dart';

import '../../../../design_system/charts/charts.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../data/physical_asset.dart';

/// Line chart of valuation history.
///
/// Manual / purchase points always show as filled dots; the projected
/// curve (vehicle auto-depreciation) is rendered as a dashed line in the
/// theme's `tertiary` color so users can tell at a glance which segments
/// came from the database vs the depreciation model.
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
    final l10n = AppLocalizations.of(context);
    return NwLineChart(
      series: [
        if (projection.length >= 2)
          ChartSeries(
            name: l10n.physicalAssetValuationProjected,
            intent: SeriesIntent.projection,
            emphasis: SeriesEmphasis.dashed,
            points: _toPoints(projection),
          ),
        if (points.isNotEmpty)
          ChartSeries(
            name: l10n.physicalAssetValuationHistorical,
            intent: SeriesIntent.primary,
            points: _toPoints(points),
          ),
      ],
      yAxis: ValueAxis.currency(currencyCode: currency),
      filled: true,
      interpolation: ChartInterpolation.linear,
      semanticLabel: l10n.physicalAssetValuationTrendSemanticLabel,
    );
  }

  static List<ChartPoint> _toPoints(List<ValuationPoint> pts) {
    final sorted = [...pts]..sort((a, b) => a.asOf.compareTo(b.asOf));
    return [
      for (final p in sorted)
        ChartPoint(
          x: p.asOf.millisecondsSinceEpoch.toDouble(),
          y: p.value.toDouble(),
          meta: p,
        ),
    ];
  }
}
