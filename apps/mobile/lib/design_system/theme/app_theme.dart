import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../tokens/typography_tokens.dart';

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
    final scheme = ColorScheme(
      brightness: brightness,
      primary: f.primary,
      onPrimary: f.primaryForeground,
      secondary: f.secondary,
      onSecondary: f.secondaryForeground,
      tertiary: f.mutedForeground,
      onTertiary: f.background,
      error: f.destructive,
      onError: f.destructiveForeground,
      surface: f.background,
      onSurface: f.foreground,
      surfaceContainerLowest: f.background,
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
      scaffoldBackgroundColor: f.background,
      visualDensity: compact
          ? VisualDensity.compact
          : VisualDensity.adaptivePlatformDensity,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      hoverColor: f.primary.withValues(alpha: 0.04),
      focusColor: f.primary.withValues(alpha: 0.06),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.macOS: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
        },
      ),
    );
  }
}
