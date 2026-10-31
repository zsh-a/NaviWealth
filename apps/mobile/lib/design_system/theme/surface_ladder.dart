import 'package:flutter/widgets.dart';

import '../tokens/color_palette.dart';
import 'app_visual_style.dart';

/// Resolved surface/content color ladder for a visual preset and brightness.
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

/// Pure resolver for surfaces, text and the platform's contrast preference.
///
/// High contrast tightens the text ladder toward WCAG AAA (7:1) on card;
/// the contrast test enforces the raised threshold for both visual presets.
AppSurfaceLadder resolveSurfaceLadder({
  required Brightness brightness,
  bool highContrast = false,
  AppVisualStyle visualStyle = AppVisualStyle.refined,
}) {
  final isDark = brightness == Brightness.dark;

  if (visualStyle == AppVisualStyle.refined) {
    return isDark
        ? AppSurfaceLadder(
            canvas: ColorPalette.refinedCanvasDark,
            card: ColorPalette.refinedCardDark,
            raised: ColorPalette.refinedRaisedDark,
            hero: ColorPalette.refinedHeroDark,
            border: highContrast
                ? ColorPalette.refinedContrastBorderDark
                : ColorPalette.refinedBorderDark,
            scrim: ColorPalette.scrimDark,
            contentStrong: ColorPalette.refinedStrongDark,
            contentBody: ColorPalette.refinedBodyDark,
            contentMuted: highContrast
                ? ColorPalette.refinedContrastMutedDark
                : ColorPalette.refinedMutedDark,
            contentFaint: ColorPalette.refinedFaintDark,
          )
        : AppSurfaceLadder(
            canvas: ColorPalette.refinedCanvasLight,
            card: ColorPalette.neutral0,
            raised: ColorPalette.refinedRaisedLight,
            hero: ColorPalette.refinedHeroLight,
            border: highContrast
                ? ColorPalette.refinedContrastBorderLight
                : ColorPalette.refinedBorderLight,
            scrim: ColorPalette.scrimLight,
            contentStrong: ColorPalette.refinedStrongLight,
            contentBody: ColorPalette.refinedBodyLight,
            contentMuted: highContrast
                ? ColorPalette.refinedContrastMutedLight
                : ColorPalette.refinedMutedLight,
            contentFaint: ColorPalette.refinedFaintLight,
          );
  }

  return isDark
      ? AppSurfaceLadder(
          canvas: ColorPalette.surfaceBackgroundDark,
          card: ColorPalette.surfaceDark,
          raised: ColorPalette.surfaceRaisedDark,
          hero: ColorPalette.surfaceHeroDark,
          border: highContrast
              ? ColorPalette.navy500
              : ColorPalette.surfaceHairlineDark,
          scrim: ColorPalette.scrimDark,
          contentStrong: ColorPalette.refinedStrongDark,
          contentBody: ColorPalette.refinedBodyDark,
          contentMuted: highContrast
              ? ColorPalette.refinedContrastMutedDark
              : ColorPalette.refinedMutedDark,
          contentFaint: highContrast
              ? ColorPalette.refinedMutedDark
              : ColorPalette.refinedFaintDark,
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
          contentStrong: ColorPalette.refinedStrongLight,
          contentBody: ColorPalette.refinedBodyLight,
          contentMuted: highContrast
              ? ColorPalette.refinedContrastMutedLight
              : ColorPalette.refinedMutedLight,
          contentFaint: highContrast
              ? ColorPalette.refinedMutedLight
              : ColorPalette.refinedFaintLight,
        );
}
