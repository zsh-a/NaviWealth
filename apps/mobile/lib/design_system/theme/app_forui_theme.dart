import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../tokens/color_palette.dart';
import '../tokens/typography_tokens.dart';
import 'accent_colors.dart';

/// Builds the production Forui theme for NaviWealth.
///
/// Slate supplies the component styles and touch/desktop density. NaviWealth's
/// brand colors then replace the palette fields shared with the Material
/// theme so both widget systems render the same surface language.
FThemeData buildAppForuiTheme({
  required Brightness brightness,
  required bool touch,
}) {
  final isDark = brightness == Brightness.dark;
  final platform = isDark ? FThemes.slate.dark : FThemes.slate.light;
  final base = touch ? platform.touch : platform.desktop;
  final colors = base.colors.copyWith(
    primary: AccentColors.primary(brightness),
    primaryForeground: AccentColors.onPrimary(brightness),
    background: isDark ? ColorPalette.navy950 : ColorPalette.surfaceBackground,
    foreground: isDark ? ColorPalette.navy50 : ColorPalette.navy900,
    mutedForeground: isDark ? ColorPalette.navy300 : ColorPalette.navy500,
    card: isDark ? ColorPalette.navyGlass : ColorPalette.surface,
    border: isDark ? ColorPalette.navy800 : ColorPalette.surfaceHairline,
    muted: isDark ? ColorPalette.navyGlass : ColorPalette.surfaceOverlay,
  );
  final inheritedTypography = FTypography.inherit(colors: colors, touch: touch);
  final typography = FTypography(
    display: _withAppFont(inheritedTypography.display),
    body: _withAppFont(inheritedTypography.body),
  );

  return FThemeData(touch: touch, typography: typography, colors: colors);
}

FTypeface _withAppFont(FTypeface base) => FTypeface(
  fontFamily: TypographyTokens.fontFamilySans,
  fontFamilyFallback: TypographyTokens.fontFamilyFallback,
  xs3: _withAppFontStyle(base.xs3),
  xs2: _withAppFontStyle(base.xs2),
  xs: _withAppFontStyle(base.xs),
  sm: _withAppFontStyle(base.sm),
  md: _withAppFontStyle(base.md),
  lg: _withAppFontStyle(base.lg),
  xl: _withAppFontStyle(base.xl),
  xl2: _withAppFontStyle(base.xl2),
  xl3: _withAppFontStyle(base.xl3),
  xl4: _withAppFontStyle(base.xl4),
  xl5: _withAppFontStyle(base.xl5),
  xl6: _withAppFontStyle(base.xl6),
  xl7: _withAppFontStyle(base.xl7),
  xl8: _withAppFontStyle(base.xl8),
);

TextStyle _withAppFontStyle(TextStyle base) => base.copyWith(
  fontFamily: TypographyTokens.fontFamilySans,
  fontFamilyFallback: TypographyTokens.fontFamilyFallback,
  fontFeatures: TypographyTokens.tabularFigures,
);
