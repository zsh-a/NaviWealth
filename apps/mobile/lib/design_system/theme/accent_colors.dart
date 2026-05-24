import 'package:flutter/material.dart';

import '../tokens/color_palette.dart';

/// Single source of truth for the accent (teal) brand color used across
/// `ColorScheme.primary`, the Forui `FColors.primary` override, chart
/// "primary series", and any insight / action card emphasis.
///
/// Resolves the right shade for the active brightness so callers do not
/// have to thread `Brightness` through their widgets.
class AccentColors {
  const AccentColors._();

  /// Foreground / interaction color (used as `colors.primary`).
  ///
  /// Light mode → teal600 (good contrast on white surfaces).
  /// Dark mode  → teal400 (lifts off slate surfaces without glare).
  static Color primary(Brightness brightness) => brightness == Brightness.dark
      ? ColorPalette.teal400
      : ColorPalette.teal600;

  /// Color drawn on top of `primary` (button labels, badge text).
  ///
  /// Both modes use a near-white tone so we don't have to flip with
  /// brightness — teal600 / teal400 both pass WCAG AA on white.
  static Color onPrimary(Brightness brightness) => brightness == Brightness.dark
      ? ColorPalette.neutral950
      : ColorPalette.neutral0;

  /// Soft tinted background (insight cards, chip backgrounds).
  static Color tint(Brightness brightness) => brightness == Brightness.dark
      ? ColorPalette.teal900
      : ColorPalette.teal50;

  /// Mid-saturation series color used by charts.
  static const Color series = ColorPalette.teal500;

  /// Translucent overlay for area-fill gradients beneath sparklines.
  static Color areaFill(Brightness brightness) =>
      primary(brightness).withValues(alpha: 0.12);
}
