import 'package:flutter/widgets.dart';

/// Brightness-aware resolution for categorical data colors (blueprint §8.7).
///
/// Expense categories, knowledge types and health metrics carry a *seed hue*
/// (a constant, or a user-stored hex riding through sync). Seeds are authored
/// for light surfaces; painted raw on a navy canvas they read harsh and
/// off-brand. Every categorical color must pass through [adapt] (or
/// [container]/[onContainer]) at render time — the one choke point where
/// dark mode gets a legible, softened variant without a second authored
/// table per category.
@immutable
class AppCategorical {
  const AppCategorical({required this.brightness, required this.cardSurface});

  final Brightness brightness;

  /// The card surface categorical containers blend into.
  final Color cardSurface;

  bool get _isDark => brightness == Brightness.dark;

  /// Foreground-grade variant of [seed] for the active brightness:
  /// dark mode lifts lightness into a legible band and caps saturation;
  /// light mode caps lightness so pale seeds don't wash out on white.
  Color adapt(Color seed) {
    final hsl = HSLColor.fromColor(seed);
    if (_isDark) {
      return hsl
          .withLightness(hsl.lightness.clamp(0.60, 0.80))
          .withSaturation(hsl.saturation.clamp(0.0, 0.70))
          .toColor();
    }
    return hsl.withLightness(hsl.lightness.clamp(0.28, 0.48)).toColor();
  }

  /// Tinted fill for chips/avatars keyed by [seed], blended into the card
  /// surface so the tint never glows on dark canvases.
  Color container(Color seed) => Color.alphaBlend(
    adapt(seed).withValues(alpha: _isDark ? 0.18 : 0.12),
    cardSurface,
  );

  /// Foreground on top of [container].
  Color onContainer(Color seed) {
    final hsl = HSLColor.fromColor(seed);
    return hsl.withLightness(_isDark ? 0.82 : 0.30).toColor();
  }
}
