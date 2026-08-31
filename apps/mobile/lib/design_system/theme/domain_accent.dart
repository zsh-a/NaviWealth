import 'package:flutter/widgets.dart';

import '../tokens/color_palette.dart';

/// Per-domain accent color, authored as a light/dark pair and resolved at
/// render time against the active brightness — the same discipline as
/// [AccentSeedSlots], so no raw single `Color` ever breaks dark mode.
///
/// A domain accent is chrome identity only (switcher chip, switcher sheet,
/// dock tab tint). It never recolors buttons, badges, or status surfaces:
/// success/warning/danger and market up/down keep their semantic roles.
/// Domains that leave `DomainPack.accent` null fall back to the global
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

/// Canonical accent per LifeOS domain.
///
/// Hue choices avoid colors that already carry app semantics — green/red are
/// market up/down (and success/danger), amber is warning, cyan-brand is the
/// global interaction primary:
///
///  * [finance] — the brand cyan ramp itself. FinanceOS is the seed,
///    always-on domain the app identity was authored for, so its accent is
///    the default primary (emerald was rejected: it collides with market
///    up/down in both red-up CN and green-up modes). Finance therefore
///    renders exactly as before under the default cyan accent seed.
///  * [health] — pink, the de-facto HealthOS hue already established by
///    `HealthMetricColors.body` ("Pink, not violet"); vitality-adjacent
///    without touching the danger rose ramp.
///  * [knowledge] — indigo/blue-violet (product decision). Uses the same
///    shades as [AccentSeedSlots.indigo]; note-type accents
///    (`KnowledgeTypeColors`, e.g. concept violet) stay independent.
///  * [execution] — orange, the action hue. The light variant mirrors
///    Tailwind orange-600 (same value as `ExpenseCategoryColors.dining`) so
///    selected labels stay legible on white; the dark variant reuses the
///    palette's [ColorPalette.orange500]. Kept out of [ColorPalette] so the
///    design-token export surface is unchanged.
abstract final class DomainAccents {
  static const DomainAccent finance = DomainAccent(
    light: ColorPalette.cyanBrand800,
    dark: ColorPalette.cyanBrand500,
  );

  static const DomainAccent health = DomainAccent(
    light: ColorPalette.chartPinkLight,
    dark: ColorPalette.chartPinkDark,
  );

  static const DomainAccent knowledge = DomainAccent(
    light: ColorPalette.indigo700,
    dark: ColorPalette.indigo400,
  );

  static const DomainAccent execution = DomainAccent(
    light: Color(0xFFEA580C),
    dark: ColorPalette.orange500,
  );
}
