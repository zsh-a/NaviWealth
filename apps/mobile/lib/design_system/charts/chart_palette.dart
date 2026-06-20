import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../theme/market_colors.dart';
import '../tokens/color_palette.dart';

/// Chart-only color sequence and theme-derived palette helpers.
///
/// `accent` colors are scoped to chart series (benchmarks, allocation slices,
/// stacked-bar segments). They resolve from chart-specific [ColorPalette]
/// tokens, not general semantic tokens, because categorical charts need
/// distinguishability rather than brand consistency.
@immutable
class ChartPalette {
  const ChartPalette({
    required this.accentSequence,
    required this.gridLine,
    required this.axisLabel,
    required this.tooltipBackground,
    required this.tooltipForeground,
    required this.dotStroke,
  });

  /// Categorical color sequence. Walk in order; wrap around when exceeded.
  /// 8 colors → up to ~8 readable series before pattern duplication kicks in.
  final List<Color> accentSequence;

  final Color gridLine;
  final Color axisLabel;
  final Color tooltipBackground;
  final Color tooltipForeground;

  /// Halo color used around touched-spot dots so the colored dot reads as
  /// raised against whatever surface holds the chart. Matches the page
  /// background — near-white in light mode, near-black in dark mode — so
  /// dark mode no longer gets a harsh white ring.
  final Color dotStroke;

  /// Build the palette from the active theme. Cached via [Theme.of] —
  /// callers should resolve this once per `build()` rather than per data
  /// point.
  factory ChartPalette.of(BuildContext context) {
    final colors = context.theme.colors;
    final isDark =
        MediaQuery.maybeOf(context)?.platformBrightness == Brightness.dark ||
        colors.brightness == Brightness.dark;
    return ChartPalette(
      accentSequence: _accentSequence(isDark: isDark),
      // Ultra-low-opacity grid — visible enough to anchor the eye when
      // a chart explicitly opts into showGrid, but never competes with
      // the data trace. Replaces the old `colors.border` (~10–15%) which
      // turned the chart into a graph-paper grid.
      gridLine: colors.foreground.withValues(alpha: isDark ? 0.06 : 0.04),
      axisLabel: colors.mutedForeground,
      tooltipBackground: colors.foreground,
      tooltipForeground: colors.background,
      dotStroke: colors.background,
    );
  }

  /// Pick a color for series index `i`, wrapping if `i >= length`.
  Color accentAt(int i) => accentSequence[i.abs() % accentSequence.length];

  static List<Color> _accentSequence({required bool isDark}) {
    // The 4th and 8th slots stay aligned with `MarketColors.up/down` so a
    // benchmark series labelled "profit" / "loss" reads the same hue as the
    // dashboard's hero number. These were swapped to emerald / soft
    // crimson; the rest of the sequence is unchanged.
    if (isDark) {
      return const [
        ColorPalette.chartCyanDark,
        ColorPalette.chartPurpleDark,
        ColorPalette.cbOrangeLight,
        ColorPalette.chartEmeraldDark,
        ColorPalette.chartPinkDark,
        ColorPalette.chartYellowDark,
        ColorPalette.chartBlueDark,
        ColorPalette.chartRoseDark,
      ];
    }
    return const [
      ColorPalette.cyan500,
      ColorPalette.chartPurpleLight,
      ColorPalette.amber500,
      ColorPalette.green600,
      ColorPalette.chartPinkLight,
      ColorPalette.chartYellowLight,
      ColorPalette.brand500,
      ColorPalette.red600,
    ];
  }
}

/// Semantic role of a series. Decides which token resolves the color.
enum SeriesIntent {
  /// User's own portfolio / focal series.
  primary,

  /// External reference (benchmark indices). Color picked from the accent
  /// sequence according to the series' position.
  benchmark,

  /// Forward-looking model output (FIRE projection, vehicle depreciation).
  /// Rendered with a subdued tint and dashed/dotted emphasis by default.
  projection,

  /// Background reference (target line, last year same period).
  muted,

  /// Positive movement / contribution. Uses [MarketColors.up].
  up,

  /// Negative movement / contribution. Uses [MarketColors.down].
  down,
}

/// Visual emphasis for a line / area series. Bar / pie series ignore this.
enum SeriesEmphasis { solid, dashed, dotted }

/// Resolves a [SeriesIntent] (and series ordinal, used by `benchmark`) to a
/// concrete color.
Color resolveSeriesColor(
  BuildContext context, {
  required SeriesIntent intent,
  required int ordinal,
  Color? override,
}) {
  if (override != null) return override;
  final colors = context.theme.colors;
  final palette = ChartPalette.of(context);
  final market = MarketColors.of(context);
  switch (intent) {
    case SeriesIntent.primary:
      return colors.primary;
    case SeriesIntent.benchmark:
      return palette.accentAt(ordinal);
    case SeriesIntent.projection:
      return colors.mutedForeground;
    case SeriesIntent.muted:
      return colors.mutedForeground;
    case SeriesIntent.up:
      return market.up;
    case SeriesIntent.down:
      return market.down;
  }
}
