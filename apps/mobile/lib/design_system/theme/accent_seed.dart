import 'package:flutter/widgets.dart';

import '../tokens/color_palette.dart';

/// User preference for the brand interaction hue.
///
/// A fourth orthogonal theme axis (with theme mode, market color, and
/// surface style). Each seed is a hand-tuned slot table — resolved by
/// `resolveAppTheme` into the `accent` [ColorRole]; contrast invariants are
/// enforced per seed by theme_contrast_test.dart.
///
/// Hues that carry app semantics (green = profit/success, red = loss,
/// amber = warning, orange = colorblind-down) are deliberately not offered.
enum AppAccentSeed {
  /// Default turquoise brand hue.
  cyan,

  /// Violet.
  violet,

  /// Indigo.
  indigo;

  String get persistedKey => name;

  static AppAccentSeed fromKey(String? raw, {AppAccentSeed? fallback}) {
    if (raw == null) return fallback ?? AppAccentSeed.cyan;
    for (final v in AppAccentSeed.values) {
      if (v.name == raw) return v;
    }
    return fallback ?? AppAccentSeed.cyan;
  }
}

/// Semantic slots one accent seed must provide. Mirrors how the cyan brand
/// ramp is consumed today so the default seed stays pixel-identical.
@immutable
class AccentSeedSlots {
  const AccentSeedSlots({
    required this.lightPrimary,
    required this.darkPrimary,
    required this.tintLight,
    required this.tintDark,
    required this.onContainerLight,
    required this.onContainerDark,
  });

  /// Interaction foreground on light surfaces (`colors.primary`).
  final Color lightPrimary;

  /// Interaction foreground on dark surfaces.
  final Color darkPrimary;

  /// Soft tinted container on light surfaces.
  final Color tintLight;

  /// Soft tinted container on dark surfaces.
  final Color tintDark;

  /// Foreground on [tintLight].
  final Color onContainerLight;

  /// Foreground on [tintDark].
  final Color onContainerDark;

  static AccentSeedSlots of(AppAccentSeed seed) => switch (seed) {
    AppAccentSeed.cyan => const AccentSeedSlots(
      lightPrimary: ColorPalette.cyanBrand800,
      darkPrimary: ColorPalette.cyanBrand500,
      tintLight: ColorPalette.surfaceOverlay,
      tintDark: ColorPalette.cyanBrand900,
      onContainerLight: ColorPalette.cyanBrand800,
      onContainerDark: ColorPalette.cyanBrand100,
    ),
    AppAccentSeed.violet => const AccentSeedSlots(
      lightPrimary: ColorPalette.violet700,
      darkPrimary: ColorPalette.violet400,
      tintLight: ColorPalette.violet50,
      tintDark: ColorPalette.violet900,
      onContainerLight: ColorPalette.violet800,
      onContainerDark: ColorPalette.violet100,
    ),
    AppAccentSeed.indigo => const AccentSeedSlots(
      lightPrimary: ColorPalette.indigo700,
      darkPrimary: ColorPalette.indigo400,
      tintLight: ColorPalette.indigo50,
      tintDark: ColorPalette.indigo900,
      onContainerLight: ColorPalette.indigo800,
      onContainerDark: ColorPalette.indigo100,
    ),
  };
}
