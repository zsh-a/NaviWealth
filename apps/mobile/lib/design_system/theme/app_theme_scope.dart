import 'package:flutter/widgets.dart';

import 'app_theme_data.dart';
import 'market_color_mode.dart';
import 'theme_resolver.dart';

/// Carries the resolved [AppThemeData] down the tree.
///
/// Installed once at the app root (`lib/app/app.dart`) from the resolved
/// brightness + market-color preference. UI code reads `context.appTheme`;
/// nothing below the root re-derives brightness or preferences.
class AppThemeScope extends InheritedWidget {
  const AppThemeScope({required this.data, required super.child, super.key});

  final AppThemeData data;

  static AppThemeData of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppThemeScope>();
    assert(scope != null, 'AppThemeScope is missing above this context.');
    return scope?.data ?? _fallback;
  }

  /// Test/edge fallback mirroring the app defaults (light, red-up).
  static final AppThemeData _fallback = resolveAppTheme(
    const ThemeInputs(
      brightness: Brightness.light,
      marketMode: MarketColorMode.redUpGreenDown,
    ),
  );

  @override
  bool updateShouldNotify(AppThemeScope oldWidget) => oldWidget.data != data;
}

/// The single theme read entry point (blueprint doc 15, §3.4).
extension AppThemeContext on BuildContext {
  AppThemeData get appTheme => AppThemeScope.of(this);
}
