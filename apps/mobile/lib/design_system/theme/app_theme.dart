import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../tokens/color_palette.dart';
import '../tokens/dimens_tokens.dart';
import '../tokens/typography_tokens.dart';
import 'accent_colors.dart';
import 'accent_seed.dart';
import 'app_page_transitions.dart';

bool useCompactDensity(TargetPlatform platform, bool isWeb) {
  if (isWeb) return true;
  return switch (platform) {
    TargetPlatform.macOS ||
    TargetPlatform.windows ||
    TargetPlatform.linux => true,
    TargetPlatform.iOS ||
    TargetPlatform.android ||
    TargetPlatform.fuchsia => false,
  };
}

/// Material [ThemeData] aligned with [buildAppForuiTheme].
///
/// Forui owns component visuals. This theme keeps Material charts, overlays,
/// and residual widgets on the same cool-canvas + cyan brand language.
class AppTheme {
  const AppTheme._();

  static ThemeData light({
    bool compact = false,
    AppAccentSeed accentSeed = AppAccentSeed.cyan,
  }) => _build(Brightness.light, compact, accentSeed);

  static ThemeData dark({
    bool compact = false,
    AppAccentSeed accentSeed = AppAccentSeed.cyan,
  }) => _build(Brightness.dark, compact, accentSeed);

  static ThemeData _build(
    Brightness brightness,
    bool compact,
    AppAccentSeed accentSeed,
  ) {
    final isDark = brightness == Brightness.dark;
    final f = isDark ? FColors.slateDark : FColors.slateLight;
    final accent = AccentColors.primary(brightness, seed: accentSeed);
    final onAccent = AccentColors.onPrimary(brightness);
    final pageBackground = isDark
        ? ColorPalette.navy950
        : ColorPalette.surfaceBackground;
    final mutedForeground = isDark
        ? ColorPalette.navy300
        : ColorPalette.navy500;
    final scheme = ColorScheme(
      brightness: brightness,
      primary: accent,
      onPrimary: onAccent,
      secondary: f.secondary,
      onSecondary: f.secondaryForeground,
      tertiary: mutedForeground,
      onTertiary: f.background,
      error: f.destructive,
      onError: f.destructiveForeground,
      surface: pageBackground,
      onSurface: isDark ? ColorPalette.navy50 : ColorPalette.navy900,
      surfaceContainerLowest: pageBackground,
      surfaceContainerLow: isDark
          ? ColorPalette.navyGlass
          : ColorPalette.surface,
      surfaceContainer: isDark
          ? ColorPalette.navyGlass
          : ColorPalette.surfaceOverlay,
      surfaceContainerHigh: f.muted,
      surfaceContainerHighest: f.secondary,
      onSurfaceVariant: mutedForeground,
      outline: isDark ? ColorPalette.navy800 : ColorPalette.surfaceHairline,
      outlineVariant: isDark
          ? ColorPalette.navy800
          : ColorPalette.surfaceHairline,
      inverseSurface: isDark ? ColorPalette.navy50 : ColorPalette.navy900,
      onInverseSurface: pageBackground,
      shadow: ColorPalette.shadowMedium,
      scrim: f.barrier,
    );
    final textTheme = TypographyTokens.textTheme().apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      textTheme: textTheme,
      scaffoldBackgroundColor: pageBackground,
      visualDensity: compact
          ? VisualDensity.compact
          : VisualDensity.adaptivePlatformDensity,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      hoverColor: accent.withValues(alpha: AppOpacity.whisper),
      focusColor: accent.withValues(alpha: AppOpacity.faint),
      // Width-aware app transition on every desktop-capable platform; iOS
      // keeps the Cupertino builder for the edge-swipe back gesture.
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: AppPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: AppPageTransitionsBuilder(),
          TargetPlatform.macOS: AppPageTransitionsBuilder(),
          TargetPlatform.windows: AppPageTransitionsBuilder(),
          TargetPlatform.fuchsia: AppPageTransitionsBuilder(),
        },
      ),
    );
  }
}
