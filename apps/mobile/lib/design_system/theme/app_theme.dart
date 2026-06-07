import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../tokens/dimens_tokens.dart';
import '../tokens/typography_tokens.dart';
import 'accent_colors.dart';

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

/// Minimal Material [ThemeData] that mirrors the active forui slate palette
/// so any residual Material widget in the tree (charts, etc.) renders in
/// step with forui visuals.
///
/// Forui owns every component visual via `FTheme(FThemes.slate.*)`. This
/// `ThemeData` exists purely to keep `Theme.of(context).colorScheme` /
/// `textTheme` answering with slate-aligned values for the long tail of
/// Material call sites still being migrated.
class AppTheme {
  const AppTheme._();

  static ThemeData light({bool compact = false}) =>
      _build(Brightness.light, compact);

  static ThemeData dark({bool compact = false}) =>
      _build(Brightness.dark, compact);

  static ThemeData _build(Brightness brightness, bool compact) {
    final isDark = brightness == Brightness.dark;
    final f = isDark ? FColors.slateDark : FColors.slateLight;
    // Override Slate's slate-grey primary with teal so the Material side of
    // the tree (residual MaterialButton / Switch / etc.) reads the same
    // brand interaction color as the forui side. See app.dart for the
    // matching FColors.copyWith on the forui surface.
    final accent = AccentColors.primary(brightness);
    final onAccent = AccentColors.onPrimary(brightness);
    // Cool-white page background per fintech spec — not pure white (which
    // reads as bare canvas) and not warm gray. Dark mode uses a deep
    // navy-tinted background for brand consistency.
    final pageBackground = isDark
        ? const Color(0xFF0A1F28)
        : const Color(0xFFFBFEFE);
    final scheme = ColorScheme(
      brightness: brightness,
      primary: accent,
      onPrimary: onAccent,
      secondary: f.secondary,
      onSecondary: f.secondaryForeground,
      tertiary: f.mutedForeground,
      onTertiary: f.background,
      error: f.destructive,
      onError: f.destructiveForeground,
      surface: pageBackground,
      onSurface: f.foreground,
      surfaceContainerLowest: pageBackground,
      surfaceContainerLow: f.card,
      surfaceContainer: f.muted,
      surfaceContainerHigh: f.muted,
      surfaceContainerHighest: f.secondary,
      onSurfaceVariant: f.mutedForeground,
      outline: f.border,
      outlineVariant: f.border,
      inverseSurface: f.foreground,
      onInverseSurface: f.background,
      shadow: const Color(0x33000000),
      scrim: f.barrier,
    );
    final textTheme = TypographyTokens.textTheme().apply(
      bodyColor: f.foreground,
      displayColor: f.foreground,
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
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.macOS: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
        },
      ),
    );
  }
}
