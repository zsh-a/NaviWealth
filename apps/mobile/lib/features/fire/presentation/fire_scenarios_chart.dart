import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../../../design_system/charts/charts.dart';
import '../domain/fire_projection.dart';

/// Multi-scenario projection chart: each scenario gets its own coloured
/// line plus a single dashed "target" line representing the inflation-
/// adjusted FIRE target over time.
///
/// The target line is shared across scenarios because the goal is
/// scenario-independent — only the path to it differs. We pick the target
/// series from the live (or neutral) scenario so the curve reflects the
/// horizon that scenario was projected against.
class FireScenariosChart extends StatelessWidget {
  const FireScenariosChart({
    super.key,
    required this.scenarios,
    required this.baseCurrency,
    required this.locale,
    required this.scenarioLabel,
    this.aspectRatio = 16 / 9,
  });

  /// Scenarios to render, in display order. The first non-empty scenario
  /// supplies the target line.
  final List<FireScenario> scenarios;

  final String baseCurrency;
  final String locale;

  /// Localiser for tier labels — passed in so the chart stays widget-test
  /// friendly without bringing AppLocalizations into the constructor.
  final String Function(FireScenarioTier) scenarioLabel;

  final double aspectRatio;

  @override
  Widget build(BuildContext context) {
    final nonEmpty = scenarios.where((s) => s.points.isNotEmpty).toList();
    if (nonEmpty.isEmpty) {
      return AspectRatio(
        aspectRatio: aspectRatio,
        child: const EmptyChartPlaceholder(),
      );
    }

    // Target series — pick from the live scenario when available, else
    // neutral, else the first available. The target curve is identical
    // across scenarios (inflation-only) so any one will do for the line
    // shape; choosing live/neutral keeps the X-axis end-points aligned
    // with the most likely user reference.
    final targetSource = nonEmpty.firstWhere(
      (s) => s.tier == FireScenarioTier.live,
      orElse: () => nonEmpty.firstWhere(
        (s) => s.tier == FireScenarioTier.neutral,
        orElse: () => nonEmpty.first,
      ),
    );

    final palette = ChartPalette.of(context);

    final series = <ChartSeries>[
      for (final s in nonEmpty)
        ChartSeries(
          name: scenarioLabel(s.tier),
          intent: SeriesIntent.benchmark,
          emphasis: SeriesEmphasis.solid,
          colorOverride: _colorFor(context, palette, s.tier),
          points: [
            for (final p in s.points)
              ChartPoint(
                x: p.date.millisecondsSinceEpoch.toDouble(),
                y: p.netWorth,
              ),
          ],
        ),
      ChartSeries(
        name: 'Target',
        intent: SeriesIntent.muted,
        emphasis: SeriesEmphasis.dashed,
        points: [
          for (final p in targetSource.points)
            ChartPoint(
              x: p.date.millisecondsSinceEpoch.toDouble(),
              y: p.target,
            ),
        ],
      ),
    ];

    return NwLineChart(
      series: series,
      aspectRatio: aspectRatio,
      xAxis: TimeAxis(
        format: AxisDateFormat.yearOnly,
        locale: locale,
        maxLabels: 6,
      ),
      yAxis: ValueAxis.currency(currencyCode: baseCurrency, locale: locale),
      semanticLabel: 'FIRE projection',
    );
  }

  /// Stable per-tier color, picked from the chart palette so dark/light
  /// theme switching just works. Intents (primary / benchmark / muted)
  /// don't quite map cleanly to the four tiers — primary would compete
  /// with the theme's CTA color and benchmark's ordinal-mapping makes it
  /// hard to keep "neutral = blue" stable as scenarios are added or
  /// reordered. An explicit override per tier keeps the legend mental
  /// model fixed.
  static Color _colorFor(
    BuildContext context,
    ChartPalette palette,
    FireScenarioTier tier,
  ) {
    switch (tier) {
      case FireScenarioTier.conservative:
        return palette.accentAt(3); // green
      case FireScenarioTier.neutral:
        return palette.accentAt(6); // blue
      case FireScenarioTier.aggressive:
        return palette.accentAt(2); // orange
      case FireScenarioTier.live:
        return context.theme.colors.primary;
    }
  }
}
