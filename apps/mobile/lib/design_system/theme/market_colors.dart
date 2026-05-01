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
@immutable
class MarketColors extends ThemeExtension<MarketColors> {
  const MarketColors({
    required this.mode,
    required this.up,
    required this.onUp,
    required this.upContainer,
    required this.onUpContainer,
    required this.down,
    required this.onDown,
    required this.downContainer,
    required this.onDownContainer,
    required this.flat,
    required this.onFlat,
  });

  /// The mode this set of colors was built from. Stored for debug tooling
  /// and for code that needs to render an icon hint (e.g. arrows next to a
  /// number) for color-blind users.
  final MarketColorMode mode;

  final Color up;
  final Color onUp;
  final Color upContainer;
  final Color onUpContainer;

  final Color down;
  final Color onDown;
  final Color downContainer;
  final Color onDownContainer;

  final Color flat;
  final Color onFlat;

  /// Pick the foreground color for a delta value.
  ///
  /// `delta == 0` (or null) renders as `flat` so widgets can pass
  /// "no-change" cleanly.
  Color forDelta(num? delta) {
    if (delta == null || delta == 0) return flat;
    return delta > 0 ? up : down;
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

    final red = _RedTone.forBrightness(isDark);
    final green = _GreenTone.forBrightness(isDark);
    final blue = _BlueTone.forBrightness(isDark);
    final orange = _OrangeTone.forBrightness(isDark);

    switch (mode) {
      case MarketColorMode.redUpGreenDown:
        return MarketColors(
          mode: mode,
          up: red.fg,
          onUp: red.onFg,
          upContainer: red.container,
          onUpContainer: red.onContainer,
          down: green.fg,
          onDown: green.onFg,
          downContainer: green.container,
          onDownContainer: green.onContainer,
          flat: flat,
          onFlat: onFlat,
        );
      case MarketColorMode.greenUpRedDown:
        return MarketColors(
          mode: mode,
          up: green.fg,
          onUp: green.onFg,
          upContainer: green.container,
          onUpContainer: green.onContainer,
          down: red.fg,
          onDown: red.onFg,
          downContainer: red.container,
          onDownContainer: red.onContainer,
          flat: flat,
          onFlat: onFlat,
        );
      case MarketColorMode.colorblind:
        return MarketColors(
          mode: mode,
          up: blue.fg,
          onUp: blue.onFg,
          upContainer: blue.container,
          onUpContainer: blue.onContainer,
          down: orange.fg,
          onDown: orange.onFg,
          downContainer: orange.container,
          onDownContainer: orange.onContainer,
          flat: flat,
          onFlat: onFlat,
        );
    }
  }

  @override
  MarketColors copyWith({
    MarketColorMode? mode,
    Color? up,
    Color? onUp,
    Color? upContainer,
    Color? onUpContainer,
    Color? down,
    Color? onDown,
    Color? downContainer,
    Color? onDownContainer,
    Color? flat,
    Color? onFlat,
  }) {
    return MarketColors(
      mode: mode ?? this.mode,
      up: up ?? this.up,
      onUp: onUp ?? this.onUp,
      upContainer: upContainer ?? this.upContainer,
      onUpContainer: onUpContainer ?? this.onUpContainer,
      down: down ?? this.down,
      onDown: onDown ?? this.onDown,
      downContainer: downContainer ?? this.downContainer,
      onDownContainer: onDownContainer ?? this.onDownContainer,
      flat: flat ?? this.flat,
      onFlat: onFlat ?? this.onFlat,
    );
  }

  @override
  MarketColors lerp(ThemeExtension<MarketColors>? other, double t) {
    if (other is! MarketColors) return this;
    return MarketColors(
      mode: t < 0.5 ? mode : other.mode,
      up: Color.lerp(up, other.up, t)!,
      onUp: Color.lerp(onUp, other.onUp, t)!,
      upContainer: Color.lerp(upContainer, other.upContainer, t)!,
      onUpContainer: Color.lerp(onUpContainer, other.onUpContainer, t)!,
      down: Color.lerp(down, other.down, t)!,
      onDown: Color.lerp(onDown, other.onDown, t)!,
      downContainer: Color.lerp(downContainer, other.downContainer, t)!,
      onDownContainer: Color.lerp(onDownContainer, other.onDownContainer, t)!,
      flat: Color.lerp(flat, other.flat, t)!,
      onFlat: Color.lerp(onFlat, other.onFlat, t)!,
    );
  }
}

class _ToneSet {
  const _ToneSet({
    required this.fg,
    required this.onFg,
    required this.container,
    required this.onContainer,
  });
  final Color fg;
  final Color onFg;
  final Color container;
  final Color onContainer;
}

class _RedTone {
  static _ToneSet forBrightness(bool isDark) {
    if (isDark) {
      return const _ToneSet(
        fg: ColorPalette.red300,
        onFg: ColorPalette.red900,
        container: Color(0xFF3D0F1A),
        onContainer: ColorPalette.red100,
      );
    }
    return const _ToneSet(
      fg: ColorPalette.red600,
      onFg: ColorPalette.neutral0,
      container: ColorPalette.red50,
      onContainer: ColorPalette.red900,
    );
  }
}

class _GreenTone {
  static _ToneSet forBrightness(bool isDark) {
    if (isDark) {
      return const _ToneSet(
        fg: ColorPalette.green300,
        onFg: ColorPalette.green900,
        container: Color(0xFF0D3326),
        onContainer: ColorPalette.green100,
      );
    }
    return const _ToneSet(
      fg: ColorPalette.green600,
      onFg: ColorPalette.neutral0,
      container: ColorPalette.green50,
      onContainer: ColorPalette.green900,
    );
  }
}

class _BlueTone {
  static _ToneSet forBrightness(bool isDark) {
    if (isDark) {
      return const _ToneSet(
        fg: ColorPalette.cbBlueLight,
        onFg: ColorPalette.cbBlueDark,
        container: ColorPalette.cbBlueContainerDark,
        onContainer: ColorPalette.cbBlueLight,
      );
    }
    return const _ToneSet(
      fg: ColorPalette.cbBlue,
      onFg: ColorPalette.neutral0,
      container: ColorPalette.cbBlueContainerLight,
      onContainer: ColorPalette.cbBlueDark,
    );
  }
}

class _OrangeTone {
  static _ToneSet forBrightness(bool isDark) {
    if (isDark) {
      return const _ToneSet(
        fg: ColorPalette.cbOrangeLight,
        onFg: ColorPalette.cbOrangeDark,
        container: ColorPalette.cbOrangeContainerDark,
        onContainer: ColorPalette.cbOrangeLight,
      );
    }
    return const _ToneSet(
      fg: ColorPalette.cbOrange,
      onFg: ColorPalette.neutral1000,
      container: ColorPalette.cbOrangeContainerLight,
      onContainer: ColorPalette.cbOrangeDark,
    );
  }
}
