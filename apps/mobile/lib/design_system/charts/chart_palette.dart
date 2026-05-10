import 'package:flutter/material.dart';

import '../theme/market_colors.dart';
import '../theme/semantic_colors.dart';

/// Chart-only color sequence and theme-derived palette helpers.
///
/// `accent` colors are scoped to chart series (benchmarks, allocation slices,
/// stacked-bar segments). They are deliberately NOT exposed in
/// [ColorPalette] / [ColorScheme] because regular UI controls should pick
/// from the semantic / market token sets — chart palettes are picked for
/// distinguishability, not for brand consistency.
@immutable
class ChartPalette {
  const ChartPalette({
    required this.accentSequence,
    required this.gridLine,
    required this.axisLabel,
    required this.tooltipBackground,
    required this.tooltipForeground,
  });

  /// Categorical color sequence. Walk in order; wrap around when exceeded.
  /// 8 colors → up to ~8 readable series before pattern duplication kicks in.
  final List<Color> accentSequence;

  final Color gridLine;
  final Color axisLabel;
  final Color tooltipBackground;
  final Color tooltipForeground;

  /// Build the palette from the active theme. Cached via [Theme.of] —
  /// callers should resolve this once per `build()` rather than per data
  /// point.
  factory ChartPalette.of(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final semantic = SemanticColors.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return ChartPalette(
      accentSequence: _accentSequence(isDark: isDark),
      gridLine: semantic.divider,
      axisLabel: scheme.onSurfaceVariant,
      tooltipBackground: scheme.inverseSurface,
      tooltipForeground: scheme.onInverseSurface,
    );
  }

  /// Pick a color for series index `i`, wrapping if `i >= length`.
  Color accentAt(int i) => accentSequence[i.abs() % accentSequence.length];

  static List<Color> _accentSequence({required bool isDark}) {
    // The 4th and 8th slots stay aligned with `MarketColors.up/down` so a
    // benchmark series labelled "profit" / "loss" reads the same hue as the
    // dashboard's hero number. FIR-104 swapped these to emerald / soft
    // crimson; the rest of the sequence is unchanged.
    if (isDark) {
      return const [
        Color(0xFF67D6F0), // cyan
        Color(0xFFB497F1), // purple
        Color(0xFFF6C863), // orange
        Color(0xFF34D399), // emerald (matches MarketColors.profit dark)
        Color(0xFFEB7BB1), // pink
        Color(0xFFE8D45A), // yellow
        Color(0xFF7AB7FB), // blue
        Color(0xFFFB7185), // rose (matches MarketColors.loss dark)
      ];
    }
    return const [
      Color(0xFF0891B2), // cyan
      Color(0xFF7C3AED), // purple
      Color(0xFFD97706), // orange
      Color(0xFF059669), // emerald (matches MarketColors.profit light)
      Color(0xFFDB2777), // pink
      Color(0xFFCA8A04), // yellow
      Color(0xFF1F6FEB), // blue
      Color(0xFFBE123C), // rose (matches MarketColors.loss light)
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
  final theme = Theme.of(context);
  final palette = ChartPalette.of(context);
  final market = MarketColors.of(context);
  switch (intent) {
    case SeriesIntent.primary:
      return theme.colorScheme.primary;
    case SeriesIntent.benchmark:
      return palette.accentAt(ordinal);
    case SeriesIntent.projection:
      return theme.colorScheme.tertiary;
    case SeriesIntent.muted:
      return theme.colorScheme.onSurfaceVariant;
    case SeriesIntent.up:
      return market.up;
    case SeriesIntent.down:
      return market.down;
  }
}
