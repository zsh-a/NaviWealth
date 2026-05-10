import 'package:flutter/material.dart';

/// Design tokens for the shadcn-flavoured AI Agent surface.
///
/// These values are intentionally independent of the main app's
/// `MaterialColorScheme` and Forui `FThemeData` — the AI panel uses a
/// distinct visual language (dense, modern, slightly higher contrast) to
/// signal "you are now in a different mode" relative to the calm financial
/// pages outside it.
@immutable
class STokens {
  const STokens._({
    required this.background,
    required this.muted,
    required this.border,
    required this.foreground,
    required this.mutedForeground,
    required this.accent,
    required this.primary,
    required this.primaryForeground,
    required this.destructive,
  });

  final Color background;
  final Color muted;
  final Color border;
  final Color foreground;
  final Color mutedForeground;
  final Color accent;
  final Color primary;
  final Color primaryForeground;
  final Color destructive;

  /// Dark-mode shadcn New-York palette: zinc-950 / zinc-50 with a slight
  /// blue tint on the primary accent.
  static const STokens dark = STokens._(
    background: Color(0xFF09090B), // zinc-950
    muted: Color(0xFF18181B), // zinc-900
    border: Color(0xFF27272A), // zinc-800
    foreground: Color(0xFFFAFAFA), // zinc-50
    mutedForeground: Color(0xFFA1A1AA), // zinc-400
    accent: Color(0xFF27272A), // zinc-800
    primary: Color(0xFFFAFAFA),
    primaryForeground: Color(0xFF18181B),
    destructive: Color(0xFFEF4444), // red-500
  );

  /// Light-mode shadcn New-York palette: white background with deep zinc
  /// text. Even on the light app theme the AI panel keeps the inverted
  /// shadcn look to preserve the visual mode shift.
  static const STokens light = STokens._(
    background: Color(0xFFFFFFFF),
    muted: Color(0xFFF4F4F5), // zinc-100
    border: Color(0xFFE4E4E7), // zinc-200
    foreground: Color(0xFF09090B),
    mutedForeground: Color(0xFF71717A), // zinc-500
    accent: Color(0xFFF4F4F5),
    primary: Color(0xFF18181B),
    primaryForeground: Color(0xFFFAFAFA),
    destructive: Color(0xFFEF4444),
  );

  /// Returns the variant matching the active Material brightness.
  static STokens of(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? STokens.dark
        : STokens.light;
  }
}

/// Spacing scale used by shadcn primitives. Tighter than the financial
/// pages on purpose — chat surfaces want higher information density.
class SSpace {
  const SSpace._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
}

/// Corner radii used by shadcn primitives.
class SRadius {
  const SRadius._();

  static const double sm = 4;
  static const double md = 6;
  static const double lg = 8;

  static const BorderRadius brSm = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius brMd = BorderRadius.all(Radius.circular(md));
  static const BorderRadius brLg = BorderRadius.all(Radius.circular(lg));
}

/// Type scale tuned for chat content: compact, monospace where helpful.
class SType {
  const SType._();

  static const String monoFamily = 'AppCnSans'; // monospace fallback retained

  static TextStyle body(BuildContext context) {
    final tokens = STokens.of(context);
    return TextStyle(
      fontSize: 14,
      height: 1.5,
      color: tokens.foreground,
      fontFamilyFallback: const ['Inter'],
    );
  }

  static TextStyle bodySm(BuildContext context) {
    final tokens = STokens.of(context);
    return TextStyle(fontSize: 13, height: 1.4, color: tokens.foreground);
  }

  static TextStyle muted(BuildContext context) {
    final tokens = STokens.of(context);
    return TextStyle(fontSize: 12, height: 1.4, color: tokens.mutedForeground);
  }

  static TextStyle label(BuildContext context) {
    final tokens = STokens.of(context);
    return TextStyle(
      fontSize: 11,
      height: 1.2,
      fontWeight: FontWeight.w500,
      color: tokens.mutedForeground,
      letterSpacing: 0.2,
    );
  }

  static TextStyle code(BuildContext context) {
    final tokens = STokens.of(context);
    return TextStyle(
      fontFamily: 'monospace',
      fontFamilyFallback: const ['Menlo', 'Consolas', 'Courier'],
      fontSize: 12,
      height: 1.45,
      color: tokens.foreground,
    );
  }
}
