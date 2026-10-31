import 'package:flutter/widgets.dart';

import '../tokens/color_palette.dart';

/// Per-domain accent color, authored as a light/dark pair and resolved at
/// render time against the active brightness — the same discipline as
/// [AccentSeedSlots], so no raw single `Color` ever breaks dark mode.
///
/// A domain accent is chrome identity only (switcher chip, switcher sheet,
/// dock tab tint). It never recolors buttons, badges, or status surfaces:
/// success/warning/danger and market up/down keep their semantic roles.
/// Domains that leave `DomainPack.shell.accent` null fall back to the global
/// primary, which is pixel-identical to pre-accent behavior.
@immutable
class DomainAccent {
  const DomainAccent({required this.light, required this.dark});

  /// Foreground on light surfaces.
  final Color light;

  /// Foreground on dark surfaces.
  final Color dark;

  /// Resolve the legible variant for [brightness].
  Color resolve(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;
}

/// Canonical chrome identity per LifeOS domain. Finance shares the iris-blue
/// interaction default; Health is pink, Knowledge violet, and Execution orange.
/// Business states and market direction retain their separate semantic roles.
abstract final class DomainAccents {
  static const DomainAccent finance = DomainAccent(
    light: ColorPalette.indigo700,
    dark: ColorPalette.indigo400,
  );

  static const DomainAccent health = DomainAccent(
    light: ColorPalette.chartPinkLight,
    dark: ColorPalette.chartPinkDark,
  );

  static const DomainAccent knowledge = DomainAccent(
    light: ColorPalette.violet700,
    dark: ColorPalette.violet400,
  );

  static const DomainAccent execution = DomainAccent(
    light: ColorPalette.orange600,
    dark: ColorPalette.orange500,
  );
}
