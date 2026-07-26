/// User preference for how theme surfaces render, orthogonal to the
/// light/dark [ThemeMode] and to [MarketColorMode].
///
/// Composed into [ThemeInputs] and resolved by `resolveAppTheme` — adding a
/// style here means adding a value table in the resolver, never touching
/// components (blueprint doc 15 §1 "扩展 = 加数据,不加代码").
enum AppSurfaceStyle {
  /// The default NaviWealth surface language.
  standard,

  /// True-black canvas for OLED displays. Only meaningful in dark mode;
  /// light mode falls back to [standard].
  oled,

  /// Tightened foreground/border roles targeting WCAG AAA (7:1) body text.
  highContrast;

  String get persistedKey => name;

  static AppSurfaceStyle fromKey(String? raw, {AppSurfaceStyle? fallback}) {
    if (raw == null) return fallback ?? AppSurfaceStyle.standard;
    for (final v in AppSurfaceStyle.values) {
      if (v.name == raw) return v;
    }
    return fallback ?? AppSurfaceStyle.standard;
  }
}
