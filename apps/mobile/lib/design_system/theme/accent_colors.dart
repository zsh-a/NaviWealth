import 'package:flutter/material.dart';

import '../tokens/color_palette.dart';

/// Single source of truth for the accent (cyan brand) color used across
/// `ColorScheme.primary`, the Forui `FColors.primary` override, chart
/// "primary series", and any insight / action card emphasis.
///
/// Resolves the right shade for the active brightness so callers do not
/// have to thread `Brightness` through their widgets.
class AccentColors {
  const AccentColors._();

  /// Foreground / interaction color (used as `colors.primary`).
  ///
  /// Light mode → cyanBrand500 (#22C8D2, strong turquoise).
  /// Dark mode  → cyanBrand400 (#5BE7EA, bright turquoise).
  static Color primary(Brightness brightness) => brightness == Brightness.dark
      ? ColorPalette.cyanBrand400
      : ColorPalette.cyanBrand500;

  /// Color drawn on top of `primary` (button labels, badge text).
  ///
  /// Both modes use a near-white tone — cyanBrand500 / cyanBrand400 both
  /// pass WCAG AA on white.
  static Color onPrimary(Brightness brightness) => brightness == Brightness.dark
      ? ColorPalette.navy950
      : ColorPalette.neutral0;

  /// Soft tinted background (insight cards, chip backgrounds).
  static Color tint(Brightness brightness) => brightness == Brightness.dark
      ? ColorPalette.cyanBrand900
      : ColorPalette.cyanBrand50;

  /// Mid-saturation series color used by charts.
  static const Color series = ColorPalette.cyanBrand500;

  /// Translucent overlay for area-fill gradients beneath sparklines.
  static Color areaFill(Brightness brightness) =>
      primary(brightness).withValues(alpha: 0.12);

  /// Warm orange secondary accent — low-frequency highlights (badges,
  /// special callouts). Not used for primary interactions.
  static const Color secondary = Color(0xFFFA6400);
}
