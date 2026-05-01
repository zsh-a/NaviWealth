import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/market_color_mode.dart';

/// Riverpod-injected [SharedPreferences] handle.
///
/// Override at app startup with the warm instance — see
/// `lib/app/bootstrap.dart`.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (_) => throw UnimplementedError(
    'sharedPreferencesProvider must be overridden in main()',
  ),
);

/// User preference: market direction color mapping (CN red-up / INTL
/// green-up / colorblind blue-orange).
final marketColorModeProvider =
    StateNotifierProvider<MarketColorModeController, MarketColorMode>((ref) {
      return MarketColorModeController(ref.watch(sharedPreferencesProvider));
    });

/// User preference: theme mode (light / dark / follow system).
final themeModeProvider = StateNotifierProvider<ThemeModeController, ThemeMode>(
  (ref) {
    return ThemeModeController(ref.watch(sharedPreferencesProvider));
  },
);

class MarketColorModeController extends StateNotifier<MarketColorMode> {
  MarketColorModeController(this._prefs) : super(_load(_prefs));

  static const String _key = 'naviwealth.theme.market_color_mode';
  final SharedPreferences _prefs;

  static MarketColorMode _load(SharedPreferences p) =>
      MarketColorMode.fromKey(p.getString(_key));

  Future<void> set(MarketColorMode mode) async {
    if (mode == state) return;
    state = mode;
    await _prefs.setString(_key, mode.persistedKey);
  }
}

class ThemeModeController extends StateNotifier<ThemeMode> {
  ThemeModeController(this._prefs) : super(_load(_prefs));

  static const String _key = 'naviwealth.theme.mode';
  final SharedPreferences _prefs;

  static ThemeMode _load(SharedPreferences p) {
    final raw = p.getString(_key);
    return switch (raw) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  Future<void> set(ThemeMode mode) async {
    if (mode == state) return;
    state = mode;
    await _prefs.setString(_key, mode.name);
  }
}
