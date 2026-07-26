import 'package:flutter/widgets.dart';

import 'market_color_mode.dart';

/// A pairing of colors that is guaranteed legible by construction.
///
/// [fg] sits directly on a surface (icons, emphasized text); [onContainer]
/// is the only legal foreground on top of [container]. Components consume a
/// whole role — never a lone color — so mispaired combinations (the audit's
/// `success`-on-`successContainer` badges) cannot be expressed.
///
/// The pairing invariants are enforced by `theme_contrast_test.dart` for
/// every resolvable [ThemeInputs] combination.
@immutable
class ColorRole {
  const ColorRole({
    required this.fg,
    required this.container,
    required this.onContainer,
  });

  /// Foreground drawn directly on the ambient surface.
  final Color fg;

  /// Fill for chips, badges, banners and other framed emphasis.
  final Color container;

  /// Foreground drawn on top of [container].
  final Color onContainer;

  @override
  bool operator ==(Object other) =>
      other is ColorRole &&
      other.fg == fg &&
      other.container == container &&
      other.onContainer == onContainer;

  @override
  int get hashCode => Object.hash(fg, container, onContainer);
}

/// Ambient surface ladder, from page canvas up to hero emphasis.
@immutable
class AppSurfaces {
  const AppSurfaces({
    required this.canvas,
    required this.card,
    required this.raised,
    required this.hero,
    required this.border,
    required this.scrim,
  });

  final Color canvas;
  final Color card;
  final Color raised;
  final Color hero;
  final Color border;
  final Color scrim;
}

/// Text emphasis ladder on regular surfaces.
@immutable
class AppContent {
  const AppContent({
    required this.strong,
    required this.body,
    required this.muted,
    required this.faint,
  });

  final Color strong;
  final Color body;
  final Color muted;
  final Color faint;
}

/// Non-directional status roles (validation, sync, warnings).
///
/// Direction-sensitive money colors live on [AppMarket]; under the default
/// red-up convention `danger` and `market.down` intentionally resolve to the
/// *same* [ColorRole] instance so the two systems can never disagree.
@immutable
class AppStatus {
  const AppStatus({
    required this.success,
    required this.warning,
    required this.danger,
    required this.info,
  });

  final ColorRole success;
  final ColorRole warning;
  final ColorRole danger;
  final ColorRole info;
}

/// Direction-sensitive market roles, resolved from the user's
/// [MarketColorMode] preference (red-up / green-up / colorblind).
@immutable
class AppMarket {
  const AppMarket({
    required this.mode,
    required this.up,
    required this.down,
    required this.flat,
    required this.upMuted,
    required this.downMuted,
    required this.profitGlow,
  });

  final MarketColorMode mode;
  final ColorRole up;
  final ColorRole down;
  final ColorRole flat;

  /// 80%-saturation foregrounds for dense delta columns.
  final Color upMuted;
  final Color downMuted;

  /// Radial glow behind hero numbers; emerald in every mode by design.
  final Color profitGlow;

  /// Resolve the role for a signed delta (null/zero → [flat]).
  ColorRole roleForDelta(num? delta) {
    if (delta == null || delta == 0) return flat;
    return delta > 0 ? up : down;
  }

  /// Muted foreground variant of [roleForDelta].
  Color mutedForDelta(num? delta) {
    if (delta == null || delta == 0) return flat.fg;
    return delta > 0 ? upMuted : downMuted;
  }
}

/// The resolved theme: one immutable value computed once per
/// (brightness × market mode × density) by `resolveAppTheme` and carried by
/// `AppThemeScope`. Read it via `context.appTheme`.
///
/// This is the single entry point that replaces the legacy quartet of
/// `SemanticColors.of` / `MarketColors.of` / `AccentColors.*` / ad-hoc
/// brightness branches (blueprint doc 15, §3). Component specs (`badge`,
/// `card`, …) and the semantic type scale join in later phases.
@immutable
class AppThemeData {
  const AppThemeData({
    required this.brightness,
    required this.surfaces,
    required this.content,
    required this.accent,
    required this.status,
    required this.market,
  });

  final Brightness brightness;
  final AppSurfaces surfaces;
  final AppContent content;

  /// Brand interaction role (buttons, links, active states).
  final ColorRole accent;

  final AppStatus status;
  final AppMarket market;
}
