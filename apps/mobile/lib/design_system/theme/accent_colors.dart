import 'package:flutter/material.dart';

import '../tokens/color_palette.dart';
import '../tokens/dimens_tokens.dart';
import 'accent_seed.dart';

/// Single source of truth for the selected interaction color used across
/// `ColorScheme.primary`, the Forui `FColors.primary` override, chart
/// "primary series", and any insight / action card emphasis.
///
/// Resolves the right shade for the active brightness so callers do not
/// have to thread `Brightness` through their widgets.
class AccentColors {
  const AccentColors._();

  /// Foreground / interaction color (used as `colors.primary`).
  ///
  /// Iris blue is the default; saved cyan and violet choices retain their ramps.
  static Color primary(
    Brightness brightness, {
    AppAccentSeed seed = AppAccentSeed.indigo,
  }) {
    final slots = AccentSeedSlots.of(seed);
    return brightness == Brightness.dark
        ? slots.darkPrimary
        : slots.lightPrimary;
  }

  /// Color drawn on top of `primary` (button labels, badge text).
  ///
  /// Light mode uses white on the interaction fill; dark mode uses deep ink.
  static Color onPrimary(Brightness brightness) => brightness == Brightness.dark
      ? ColorPalette.navy950
      : ColorPalette.neutral0;

  /// Foreground on [tint] for the given seed.
  static Color onTint(Brightness brightness, {required AppAccentSeed seed}) {
    final slots = AccentSeedSlots.of(seed);
    return brightness == Brightness.dark
        ? slots.onContainerDark
        : slots.onContainerLight;
  }

  /// Soft tinted background (insight cards, chip backgrounds).
  static Color tint(
    Brightness brightness, {
    AppAccentSeed seed = AppAccentSeed.indigo,
  }) {
    final slots = AccentSeedSlots.of(seed);
    return brightness == Brightness.dark ? slots.tintDark : slots.tintLight;
  }

  /// Mid-saturation series color used by charts.
  static const Color series = ColorPalette.cyanBrand600;

  /// Translucent overlay for area-fill gradients beneath sparklines.
  static Color areaFill(Brightness brightness) =>
      primary(brightness).withValues(alpha: AppOpacity.subtle);
}
