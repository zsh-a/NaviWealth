import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../tokens/color_palette.dart';
import '../tokens/dimens_tokens.dart';
import '../tokens/typography_tokens.dart';
import 'accent_colors.dart';
import 'accent_seed.dart';
import 'app_surface_style.dart';
import 'app_type_scale.dart';
import 'surface_ladder.dart';

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
  // Surface/content ramp comes from the shared ladder (surface_ladder.dart)
  // so forui widgets sit on the same canvas as design-system components.
  final ladder = resolveSurfaceLadder(
    brightness: brightness,
    surfaceStyle: surfaceStyle,
  );
  final platform = isDark ? FTheme.neutral.dark : FTheme.neutral.light;
  final base = touch ? platform.touch : platform.desktop;
  final colors = base.colors.copyWith(
    primary: AccentColors.primary(brightness, seed: accentSeed),
    primaryForeground: AccentColors.onPrimary(brightness),
    background: ladder.canvas,
    foreground: ladder.contentBody,
    mutedForeground: ladder.contentMuted,
    card: ladder.card,
    border: ladder.border,
    // Muted fills stay cooler than pure slate so SoftCard modules lift cleanly.
    muted: isDark
        ? Color.alphaBlend(
            ColorPalette.navy50.withValues(alpha: AppOpacity.whisper),
            ColorPalette.navyGlass,
          )
        : ColorPalette.surfaceOverlay,
    // Single scrim source for every overlay (sheets, dialogs, popovers):
    // the same value that AppSurfaces.scrim exposes.
    barrier: ladder.scrim,
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
