import 'package:flutter/widgets.dart';

import '../tokens/color_palette.dart';
import 'app_surface_style.dart';

/// Resolved surface/content color ladder for one brightness + surface style.
///
/// Single source of truth for the elevation ramp (canvas → card → raised →
/// hero), borders, scrims, and the text emphasis ladder. Consumed by
/// `resolveAppTheme` (AppSurfaces/AppContent), [AppTheme] (Material
/// ColorScheme), and `buildAppForuiTheme` (FColors) so all three widget
/// systems sit on the same canvas without hand-synced value tables.
@immutable
class AppSurfaceLadder {
  const AppSurfaceLadder({
    required this.canvas,
    required this.card,
    required this.raised,
    required this.hero,
    required this.border,
    required this.scrim,
    required this.contentStrong,
    required this.contentBody,
    required this.contentMuted,
    required this.contentFaint,
  });

  final Color canvas;
  final Color card;
  final Color raised;
  final Color hero;
  final Color border;
  final Color scrim;
  final Color contentStrong;
  final Color contentBody;
  final Color contentMuted;
  final Color contentFaint;
}

/// Pure resolver: brightness + [AppSurfaceStyle] → [AppSurfaceLadder].
///
/// OLED is a dark-only override; light mode falls back to standard.
/// High contrast tightens the text ladder toward WCAG AAA (7:1) on card;
/// the contrast test enforces the raised threshold per style.
AppSurfaceLadder resolveSurfaceLadder({
  required Brightness brightness,
  required AppSurfaceStyle surfaceStyle,
}) {
  final isDark = brightness == Brightness.dark;
  final oled = surfaceStyle == AppSurfaceStyle.oled && isDark;
  final highContrast = surfaceStyle == AppSurfaceStyle.highContrast;

  return isDark
      ? AppSurfaceLadder(
          canvas: oled ? ColorPalette.oledCanvas : ColorPalette.navy950,
          card: oled ? ColorPalette.oledCard : ColorPalette.navyGlass,
          raised: oled ? ColorPalette.oledRaised : ColorPalette.navyRaised,
          hero: oled ? ColorPalette.oledHero : ColorPalette.navyHero,
          border: highContrast ? ColorPalette.navy500 : ColorPalette.navy800,
          scrim: ColorPalette.scrimDark,
          contentStrong: ColorPalette.neutral0,
          contentBody: ColorPalette.navy50,
          contentMuted: highContrast
              ? ColorPalette.navy100
              : ColorPalette.navy300,
          contentFaint: highContrast
              ? ColorPalette.navy300
              : ColorPalette.navy400,
        )
      : AppSurfaceLadder(
          canvas: ColorPalette.surfaceBackground,
          card: ColorPalette.surface,
          raised: ColorPalette.surfaceRaised,
          hero: ColorPalette.surfaceHero,
          border: highContrast
              ? ColorPalette.navy400
              : ColorPalette.surfaceHairline,
          scrim: ColorPalette.scrimLight,
          contentStrong: ColorPalette.neutral1000,
          contentBody: ColorPalette.navy900,
          contentMuted: highContrast
              ? ColorPalette.navy700
              : ColorPalette.navy500,
          contentFaint: highContrast
              ? ColorPalette.navy500
              : ColorPalette.neutral400,
        );
}
