import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../tokens/color_palette.dart';
import '../tokens/dimens_tokens.dart';
import '../tokens/typography_tokens.dart';
import 'accent_colors.dart';
import 'accent_seed.dart';
import 'app_surface_style.dart';
import 'app_type_scale.dart';

/// Builds the production Forui theme for NaviWealth.
///
/// Neutral supplies the component styles and touch/desktop density. NaviWealth's
/// brand colors then replace the palette fields shared with the Material
/// theme so both widget systems render the same surface language.
FThemeData buildAppForuiTheme({
  required Brightness brightness,
  required bool touch,
  AppSurfaceStyle surfaceStyle = AppSurfaceStyle.standard,
  AppAccentSeed accentSeed = AppAccentSeed.cyan,
}) {
  final isDark = brightness == Brightness.dark;
  // Keep these in lockstep with resolveAppTheme's surface/content tables —
  // forui widgets must sit on the same canvas as design-system components.
  final oled = surfaceStyle == AppSurfaceStyle.oled && isDark;
  final highContrast = surfaceStyle == AppSurfaceStyle.highContrast;
  final platform = isDark ? FTheme.neutral.dark : FTheme.neutral.light;
  final base = touch ? platform.touch : platform.desktop;
  final colors = base.colors.copyWith(
    primary: AccentColors.primary(brightness, seed: accentSeed),
    primaryForeground: AccentColors.onPrimary(brightness),
    background: isDark
        ? (oled ? ColorPalette.oledCanvas : ColorPalette.navy950)
        : ColorPalette.surfaceBackground,
    foreground: isDark ? ColorPalette.navy50 : ColorPalette.navy900,
    mutedForeground: isDark
        ? (highContrast ? ColorPalette.navy100 : ColorPalette.navy300)
        : (highContrast ? ColorPalette.navy700 : ColorPalette.navy500),
    card: isDark
        ? (oled ? ColorPalette.oledCard : ColorPalette.navyGlass)
        : ColorPalette.surface,
    border: isDark
        ? (highContrast ? ColorPalette.navy500 : ColorPalette.navy800)
        : (highContrast ? ColorPalette.navy400 : ColorPalette.surfaceHairline),
    // Muted fills stay cooler than pure slate so SoftCard modules lift cleanly.
    muted: isDark
        ? Color.alphaBlend(
            ColorPalette.navy50.withValues(alpha: AppOpacity.whisper),
            ColorPalette.navyGlass,
          )
        : ColorPalette.surfaceOverlay,
    // Single scrim source for every overlay (sheets, dialogs, popovers):
    // the same palette values that AppSurfaces.scrim exposes.
    barrier: isDark ? ColorPalette.scrimDark : ColorPalette.scrimLight,
  );
  // One authored slot table for every density (see kAppTypefaceSlots) —
  // the legacy touch/desktop ±2px fork is deliberately gone. Density still
  // selects Forui's touch vs desktop *component* styles (padding, targets).
  final typeface = _buildAppTypeface(colors.foreground);
  final typography = FTypography(display: typeface, body: typeface);

  return FThemeData(touch: touch, typography: typography, colors: colors);
}

FTypeface _buildAppTypeface(Color foreground) {
  TextStyle slot(int index) {
    final spec = kAppTypefaceSlots[index];
    return TextStyle(
      color: foreground,
      fontFamily: TypographyTokens.fontFamilySans,
      fontFamilyFallback: TypographyTokens.fontFamilyFallback,
      fontFeatures: TypographyTokens.tabularFigures,
      fontSize: spec.size,
      height: spec.height,
      leadingDistribution: TextLeadingDistribution.even,
    );
  }

  return FTypeface(
    fontFamily: TypographyTokens.fontFamilySans,
    fontFamilyFallback: TypographyTokens.fontFamilyFallback,
    xs3: slot(0),
    xs2: slot(1),
    xs: slot(2),
    sm: slot(3),
    md: slot(4),
    lg: slot(5),
    xl: slot(6),
    xl2: slot(7),
    xl3: slot(8),
    xl4: slot(9),
    xl5: slot(10),
    xl6: slot(11),
    xl7: slot(12),
    xl8: slot(13),
  );
}
