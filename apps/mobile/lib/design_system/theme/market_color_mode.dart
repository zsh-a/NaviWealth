/// User preference for which color signals "up" vs "down" on charts and
/// money deltas.
enum MarketColorMode {
  /// 中国习惯：红涨绿跌 (default).
  redUpGreenDown,

  /// 国际习惯：绿涨红跌.
  greenUpRedDown,

  /// Color-blind friendly: blue (up) / orange (down) using the
  /// Wong / Okabe-Ito palette. Distinguishable under deuteranopia,
  /// protanopia and tritanopia.
  colorblind;

  String get persistedKey => name;

  static MarketColorMode fromKey(String? raw, {MarketColorMode? fallback}) {
    if (raw == null) return fallback ?? MarketColorMode.redUpGreenDown;
    for (final v in MarketColorMode.values) {
      if (v.name == raw) return v;
    }
    return fallback ?? MarketColorMode.redUpGreenDown;
  }
}
