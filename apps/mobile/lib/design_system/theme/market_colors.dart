import 'package:flutter/widgets.dart';

import '../tokens/color_palette.dart';
import '../tokens/dimens_tokens.dart';
import 'market_color_mode.dart';

/// Direction-sensitive color tokens (gain / loss / flat).
///
/// The actual colors swap when the user changes [MarketColorMode] in
/// settings. This table now feeds `resolveAppTheme` exclusively — UI code
/// reads `context.appTheme.market` roles; the old inherited scope and
/// `MarketColors.of` lookup are retired (doc 15 P5).
@immutable
class MarketColors {
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
  /// `RadialGradient(colors: [profitGlow, profitGlow.withValues(alpha: AppOpacity.transparent)])`.
  /// Follows the [up] hue of the active [mode] (at [AppOpacity.glow]) so
  /// the hero treatment always matches the direction colors on screen —
  /// e.g. red-up (CN) mode gets a red glow, not a green one.
  final Color profitGlow;

  /// Pick the foreground color for a delta value.
  Color forDelta(num? delta) {
    if (delta == null || delta == 0) return flat;
    return delta > 0 ? up : down;
  }

  /// Muted variant of [forDelta].
  Color mutedForDelta(num? delta) {
    if (delta == null || delta == 0) return flat;
    return delta > 0 ? upMuted : downMuted;
  }

  /// Container/background variant for a delta value.
  Color containerForDelta(num? delta) {
    if (delta == null || delta == 0) {
      return flat.withValues(alpha: AppOpacity.light);
    }
    return delta > 0 ? upContainer : downContainer;
  }

  /// On-container foreground variant for a delta value.
  Color onContainerForDelta(num? delta) {
    if (delta == null || delta == 0) return onFlat;
    return delta > 0 ? onUpContainer : onDownContainer;
  }

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
          profitGlow: loss.fg.withValues(alpha: AppOpacity.glow),
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
          profitGlow: profit.fg.withValues(alpha: AppOpacity.glow),
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
          profitGlow: blue.fg.withValues(alpha: AppOpacity.glow),
        );
    }
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

Color _muted(Color c) {
  final hsl = HSLColor.fromColor(c);
  return hsl.withSaturation((hsl.saturation * 0.8).clamp(0.0, 1.0)).toColor();
}

class _LossTone {
  static _ToneSet forBrightness(bool isDark) {
    if (isDark) {
      return _ToneSet(
        fg: ColorPalette.red500,
        mutedFg: _muted(ColorPalette.red500),
        onFg: ColorPalette.neutral0,
        container: ColorPalette.redContainerDark,
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
        fg: ColorPalette.green500,
        mutedFg: _muted(ColorPalette.green500),
        onFg: ColorPalette.neutral0,
        container: ColorPalette.greenContainerDark,
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
    // Foreground uses the dark orange: Okabe-Ito orange (#E69F00) is only
    // ~2.3:1 on white cards (doc 15 §3.1). The bright hue survives in the
    // container/chart roles where it doesn't carry small text.
    return _ToneSet(
      fg: ColorPalette.cbOrangeDark,
      mutedFg: _muted(ColorPalette.cbOrangeDark),
      onFg: ColorPalette.neutral0,
      container: ColorPalette.cbOrangeContainerLight,
      onContainer: ColorPalette.cbOrangeDark,
    );
  }
}
