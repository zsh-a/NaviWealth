import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../tokens/color_palette.dart';
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

  return FThemeData(
    touch: touch,
    colors: base.colors.copyWith(
      primary: AccentColors.primary(brightness),
      primaryForeground: AccentColors.onPrimary(brightness),
      background: isDark ? ColorPalette.navy950 : ColorPalette.neutralGlass,
      foreground: isDark ? ColorPalette.navy50 : ColorPalette.navy900,
      mutedForeground: isDark ? ColorPalette.navy300 : ColorPalette.navy500,
      card: isDark ? ColorPalette.navyGlass : ColorPalette.neutral0,
      border: isDark ? ColorPalette.navy800 : ColorPalette.neutralGlassBorder,
      muted: isDark ? ColorPalette.navyGlass : ColorPalette.neutralTint,
    ),
  );
}
