import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../tokens/breakpoints.dart';
import '../tokens/color_palette.dart';
import '../tokens/dimens_tokens.dart';
import '../tokens/typography_tokens.dart';
import 'accent_colors.dart';
import 'accent_seed.dart';
import 'app_page_transitions.dart';
import 'app_surface_style.dart';
import 'surface_ladder.dart';

/// Resolves pointer-oriented density from both platform and window class.
///
/// Web is not inherently desktop: a compact browser viewport is normally a
/// phone and must retain touch-sized targets. Native desktop stays compact;
/// native mobile stays touch-oriented regardless of window resizing.
bool useCompactDensity(
  TargetPlatform platform,
  bool isWeb, {
  double? windowWidth,
}) {
  if (isWeb) {
    return windowWidth == null || windowWidth >= Breakpoints.mobile;
  }
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
    AppSurfaceStyle surfaceStyle = AppSurfaceStyle.standard,
  }) => _build(Brightness.light, compact, accentSeed, surfaceStyle);

  static ThemeData dark({
    bool compact = false,
    AppAccentSeed accentSeed = AppAccentSeed.cyan,
    AppSurfaceStyle surfaceStyle = AppSurfaceStyle.standard,
  }) => _build(Brightness.dark, compact, accentSeed, surfaceStyle);

  static ThemeData _build(
    Brightness brightness,
    bool compact,
    AppAccentSeed accentSeed,
    AppSurfaceStyle surfaceStyle,
  ) {
    final isDark = brightness == Brightness.dark;
    // Surface/content ramp comes from the shared ladder (surface_ladder.dart)
    // so widgets that fall through to Material chrome (Scaffold backgrounds,
    // overlays) sit on the same canvas as the design system.
    final ladder = resolveSurfaceLadder(
      brightness: brightness,
      surfaceStyle: surfaceStyle,
    );
    final f = isDark ? FColors.neutralDark : FColors.neutralLight;
    final accent = AccentColors.primary(brightness, seed: accentSeed);
    final onAccent = AccentColors.onPrimary(brightness);
    final pageBackground = ladder.canvas;
    final cardSurface = ladder.card;
    final mutedForeground = ladder.contentMuted;
    final outline = ladder.border;
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
      onSurface: ladder.contentBody,
      surfaceContainerLowest: pageBackground,
      surfaceContainerLow: cardSurface,
      surfaceContainer: isDark ? cardSurface : ColorPalette.surfaceOverlay,
      surfaceContainerHigh: f.muted,
      surfaceContainerHighest: f.secondary,
      onSurfaceVariant: mutedForeground,
      outline: outline,
      outlineVariant: outline,
      inverseSurface: ladder.contentBody,
      onInverseSurface: pageBackground,
      shadow: ColorPalette.shadowMedium,
      scrim: ladder.scrim,
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
