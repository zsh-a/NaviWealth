import 'package:flutter/material.dart';

import '../tokens/color_palette.dart';
import 'market_color_mode.dart';

/// Direction-sensitive color tokens (gain / loss / flat) carried on the
/// active [ThemeData].
///
/// The actual colors swap when the user changes [MarketColorMode] in
/// settings. Widgets should ask `MarketColors.of(context).up` rather than
/// hard-coding "green" or "red" — the whole point of this extension is that
/// "up" is wired to the user's preferred convention.
///
/// FIR-104: profit migrated to emerald, loss to soft crimson, and two new
/// fields were added so dense lists can read calmly:
///
/// - [upMuted] / [downMuted] — 80%-saturation pair, used by in-row delta
///   text so a long list doesn't look like fireworks.
/// - [profitGlow] — radial-gradient inner color for the hero number on the
///   home dashboard (40% alpha emerald, fading out around 30% radius).
@immutable
class MarketColors extends ThemeExtension<MarketColors> {
  const MarketColors({
    required this.mode,
    required this.up,
    required this.upMuted,
    required this.onUp,
    required this.upContainer,
    required this.onUpContainer,
    required this.down,
    required this.downMuted,
    required this.onDown,
    required this.downContainer,
    required this.onDownContainer,
    required this.flat,
    required this.onFlat,
    required this.profitGlow,
  });

  /// The mode this set of colors was built from. Stored for debug tooling
  /// and for code that needs to render an icon hint (e.g. arrows next to a
  /// number) for color-blind users.
  final MarketColorMode mode;

  final Color up;

  /// 80% saturation [up] — for in-row deltas where the full hue is too loud.
  final Color upMuted;
  final Color onUp;
  final Color upContainer;
  final Color onUpContainer;

  final Color down;

  /// 80% saturation [down] — paired with [upMuted].
  final Color downMuted;
  final Color onDown;
  final Color downContainer;
  final Color onDownContainer;

  final Color flat;
  final Color onFlat;

  /// Inner color of the radial profit-glow used behind hero numbers. The
  /// outer stop is fully transparent — render as
  /// `RadialGradient(colors: [profitGlow, profitGlow.withValues(alpha: 0)])`.
  /// Always emerald-tinted regardless of [mode] so the visual treatment
  /// stays "this is your money, in the green" even under green-down or
  /// colorblind preferences.
  final Color profitGlow;

  /// Pick the foreground color for a delta value.
  ///
  /// `delta == 0` (or null) renders as `flat` so widgets can pass
  /// "no-change" cleanly.
  Color forDelta(num? delta) {
    if (delta == null || delta == 0) return flat;
    return delta > 0 ? up : down;
  }

  /// Muted variant of [forDelta] — pick the 80%-saturation tone so list-row
  /// deltas don't compete with hero numbers.
  Color mutedForDelta(num? delta) {
    if (delta == null || delta == 0) return flat;
    return delta > 0 ? upMuted : downMuted;
  }

  /// Container/background variant for a delta value.
  Color containerForDelta(num? delta) {
    if (delta == null || delta == 0) {
      return flat.withValues(alpha: 0.12);
    }
    return delta > 0 ? upContainer : downContainer;
  }

  /// On-container foreground variant for a delta value.
  Color onContainerForDelta(num? delta) {
    if (delta == null || delta == 0) return onFlat;
    return delta > 0 ? onUpContainer : onDownContainer;
  }

  static MarketColors of(BuildContext context) =>
      Theme.of(context).extension<MarketColors>() ??
      MarketColors.fromMode(
        MarketColorMode.redUpGreenDown,
        brightness: Brightness.light,
      );

  /// Build a [MarketColors] for a given user mode + theme brightness.
  factory MarketColors.fromMode(
    MarketColorMode mode, {
    required Brightness brightness,
  }) {
    final isDark = brightness == Brightness.dark;
    final flat = isDark ? ColorPalette.neutral400 : ColorPalette.neutral500;
    final onFlat = isDark ? ColorPalette.neutral100 : ColorPalette.neutral800;

    final loss = _LossTone.forBrightness(isDark);
    final profit = _ProfitTone.forBrightness(isDark);
    final blue = _BlueTone.forBrightness(isDark);
    final orange = _OrangeTone.forBrightness(isDark);

    // Profit glow is hue-locked to emerald regardless of red/green swap so
    // the home-dashboard hero treatment doesn't invert under the CN
    // red-up convention.
    final glow = isDark
        ? const Color(0x6610B981) // emerald 500 @ 40% alpha
        : const Color(0x66059669); // emerald 600 @ 40% alpha

    switch (mode) {
      case MarketColorMode.redUpGreenDown:
        return MarketColors(
          mode: mode,
          up: loss.fg,
          upMuted: loss.mutedFg,
          onUp: loss.onFg,
          upContainer: loss.container,
          onUpContainer: loss.onContainer,
          down: profit.fg,
          downMuted: profit.mutedFg,
          onDown: profit.onFg,
          downContainer: profit.container,
          onDownContainer: profit.onContainer,
          flat: flat,
          onFlat: onFlat,
          profitGlow: glow,
        );
      case MarketColorMode.greenUpRedDown:
        return MarketColors(
          mode: mode,
          up: profit.fg,
          upMuted: profit.mutedFg,
          onUp: profit.onFg,
          upContainer: profit.container,
          onUpContainer: profit.onContainer,
          down: loss.fg,
          downMuted: loss.mutedFg,
          onDown: loss.onFg,
          downContainer: loss.container,
          onDownContainer: loss.onContainer,
          flat: flat,
          onFlat: onFlat,
          profitGlow: glow,
        );
      case MarketColorMode.colorblind:
        return MarketColors(
          mode: mode,
          up: blue.fg,
          upMuted: blue.mutedFg,
          onUp: blue.onFg,
          upContainer: blue.container,
          onUpContainer: blue.onContainer,
          down: orange.fg,
          downMuted: orange.mutedFg,
          onDown: orange.onFg,
          downContainer: orange.container,
          onDownContainer: orange.onContainer,
          flat: flat,
          onFlat: onFlat,
          profitGlow: glow,
        );
    }
  }

  @override
  MarketColors copyWith({
    MarketColorMode? mode,
    Color? up,
    Color? upMuted,
    Color? onUp,
    Color? upContainer,
    Color? onUpContainer,
    Color? down,
    Color? downMuted,
    Color? onDown,
    Color? downContainer,
    Color? onDownContainer,
    Color? flat,
    Color? onFlat,
    Color? profitGlow,
  }) {
    return MarketColors(
      mode: mode ?? this.mode,
      up: up ?? this.up,
      upMuted: upMuted ?? this.upMuted,
      onUp: onUp ?? this.onUp,
      upContainer: upContainer ?? this.upContainer,
      onUpContainer: onUpContainer ?? this.onUpContainer,
      down: down ?? this.down,
      downMuted: downMuted ?? this.downMuted,
      onDown: onDown ?? this.onDown,
      downContainer: downContainer ?? this.downContainer,
      onDownContainer: onDownContainer ?? this.onDownContainer,
      flat: flat ?? this.flat,
      onFlat: onFlat ?? this.onFlat,
      profitGlow: profitGlow ?? this.profitGlow,
    );
  }

  @override
  MarketColors lerp(ThemeExtension<MarketColors>? other, double t) {
    if (other is! MarketColors) return this;
    return MarketColors(
      mode: t < 0.5 ? mode : other.mode,
      up: Color.lerp(up, other.up, t)!,
      upMuted: Color.lerp(upMuted, other.upMuted, t)!,
      onUp: Color.lerp(onUp, other.onUp, t)!,
      upContainer: Color.lerp(upContainer, other.upContainer, t)!,
      onUpContainer: Color.lerp(onUpContainer, other.onUpContainer, t)!,
      down: Color.lerp(down, other.down, t)!,
      downMuted: Color.lerp(downMuted, other.downMuted, t)!,
      onDown: Color.lerp(onDown, other.onDown, t)!,
      downContainer: Color.lerp(downContainer, other.downContainer, t)!,
      onDownContainer: Color.lerp(onDownContainer, other.onDownContainer, t)!,
      flat: Color.lerp(flat, other.flat, t)!,
      onFlat: Color.lerp(onFlat, other.onFlat, t)!,
      profitGlow: Color.lerp(profitGlow, other.profitGlow, t)!,
    );
  }
}

class _ToneSet {
  const _ToneSet({
    required this.fg,
    required this.mutedFg,
    required this.onFg,
    required this.container,
    required this.onContainer,
  });
  final Color fg;
  final Color mutedFg;
  final Color onFg;
  final Color container;
  final Color onContainer;
}

/// 80%-saturation HSL nudge of [c]. Caches no result — the call sites
/// build a single [MarketColors] per theme so this runs at most twice per
/// rebuild.
Color _muted(Color c) {
  final hsl = HSLColor.fromColor(c);
  return hsl.withSaturation((hsl.saturation * 0.8).clamp(0.0, 1.0)).toColor();
}

class _LossTone {
  static _ToneSet forBrightness(bool isDark) {
    if (isDark) {
      return _ToneSet(
        fg: ColorPalette.red500, // rose 500 — emerald's loss counterpart
        mutedFg: _muted(ColorPalette.red500),
        onFg: ColorPalette.neutral0,
        container: const Color(0xFF3F0A1A), // dark rose container
        onContainer: ColorPalette.red100,
      );
    }
    return _ToneSet(
      fg: ColorPalette.red600,
      mutedFg: _muted(ColorPalette.red600),
      onFg: ColorPalette.neutral0,
      container: ColorPalette.red50,
      onContainer: ColorPalette.red900,
    );
  }
}

class _ProfitTone {
  static _ToneSet forBrightness(bool isDark) {
    if (isDark) {
      return _ToneSet(
        fg: ColorPalette.green500, // emerald 500
        mutedFg: _muted(ColorPalette.green500),
        onFg: ColorPalette.neutral0,
        container: const Color(0xFF053527), // dark emerald container
        onContainer: ColorPalette.green100,
      );
    }
    return _ToneSet(
      fg: ColorPalette.green600,
      mutedFg: _muted(ColorPalette.green600),
      onFg: ColorPalette.neutral0,
      container: ColorPalette.green50,
      onContainer: ColorPalette.green900,
    );
  }
}

class _BlueTone {
  static _ToneSet forBrightness(bool isDark) {
    if (isDark) {
      return _ToneSet(
        fg: ColorPalette.cbBlueLight,
        mutedFg: _muted(ColorPalette.cbBlueLight),
        onFg: ColorPalette.cbBlueDark,
        container: ColorPalette.cbBlueContainerDark,
        onContainer: ColorPalette.cbBlueLight,
      );
    }
    return _ToneSet(
      fg: ColorPalette.cbBlue,
      mutedFg: _muted(ColorPalette.cbBlue),
      onFg: ColorPalette.neutral0,
      container: ColorPalette.cbBlueContainerLight,
      onContainer: ColorPalette.cbBlueDark,
    );
  }
}

class _OrangeTone {
  static _ToneSet forBrightness(bool isDark) {
    if (isDark) {
      return _ToneSet(
        fg: ColorPalette.cbOrangeLight,
        mutedFg: _muted(ColorPalette.cbOrangeLight),
        onFg: ColorPalette.cbOrangeDark,
        container: ColorPalette.cbOrangeContainerDark,
        onContainer: ColorPalette.cbOrangeLight,
      );
    }
    return _ToneSet(
      fg: ColorPalette.cbOrange,
      mutedFg: _muted(ColorPalette.cbOrange),
      onFg: ColorPalette.neutral1000,
      container: ColorPalette.cbOrangeContainerLight,
      onContainer: ColorPalette.cbOrangeDark,
    );
  }
}
