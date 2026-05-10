import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

/// Tokens for the AI Agent surface, delegating to the active forui slate
/// theme. Historically these duplicated zinc; now they alias forui colors
/// so the chat panel renders in step with the rest of the app.
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

  /// Resolve from the active [FTheme] colors. Both light and dark fall out
  /// of the active palette automatically.
  static STokens of(BuildContext context) {
    final c = context.theme.colors;
    return STokens._(
      background: c.background,
      muted: c.muted,
      border: c.border,
      foreground: c.foreground,
      mutedForeground: c.mutedForeground,
      accent: c.secondary,
      primary: c.primary,
      primaryForeground: c.primaryForeground,
      destructive: c.destructive,
    );
  }
}

class SSpace {
  const SSpace._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
}

class SRadius {
  const SRadius._();

  static const double sm = 4;
  static const double md = 6;
  static const double lg = 8;

  static const BorderRadius brSm = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius brMd = BorderRadius.all(Radius.circular(md));
  static const BorderRadius brLg = BorderRadius.all(Radius.circular(lg));
}

/// Type scale tuned for chat content. Pulled from forui's typography so
/// the chat panel doesn't drift from the rest of the app.
class SType {
  const SType._();

  static TextStyle body(BuildContext context) => context.theme.typography.sm
      .copyWith(height: 1.5, color: context.theme.colors.foreground);

  static TextStyle bodySm(BuildContext context) => context.theme.typography.xs
      .copyWith(height: 1.4, color: context.theme.colors.foreground);

  static TextStyle muted(BuildContext context) => context.theme.typography.xs
      .copyWith(height: 1.4, color: context.theme.colors.mutedForeground);

  static TextStyle label(BuildContext context) => TextStyle(
    fontSize: 11,
    height: 1.2,
    fontWeight: FontWeight.w500,
    color: context.theme.colors.mutedForeground,
    letterSpacing: 0.2,
  );

  static TextStyle code(BuildContext context) => TextStyle(
    fontFamily: 'monospace',
    fontFamilyFallback: const ['Menlo', 'Consolas', 'Courier'],
    fontSize: 12,
    height: 1.45,
    color: context.theme.colors.foreground,
  );
}
