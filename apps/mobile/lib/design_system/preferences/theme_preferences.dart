import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/accent_seed.dart';
import '../theme/app_surface_style.dart';
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

/// User preference: accent seed (brand hue).
final accentSeedProvider =
    StateNotifierProvider<AccentSeedController, AppAccentSeed>((ref) {
      return AccentSeedController(ref.watch(sharedPreferencesProvider));
    });

/// User preference: surface style (standard / OLED black / high contrast).
final surfaceStyleProvider =
    StateNotifierProvider<SurfaceStyleController, AppSurfaceStyle>((ref) {
      return SurfaceStyleController(ref.watch(sharedPreferencesProvider));
    });

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

class AccentSeedController extends StateNotifier<AppAccentSeed> {
  AccentSeedController(this._prefs) : super(_load(_prefs));

  static const String _key = 'naviwealth.theme.accent_seed';
  final SharedPreferences _prefs;

  static AppAccentSeed _load(SharedPreferences p) =>
      AppAccentSeed.fromKey(p.getString(_key));

  Future<void> set(AppAccentSeed seed) async {
    if (seed == state) return;
    state = seed;
    await _prefs.setString(_key, seed.persistedKey);
  }
}

class SurfaceStyleController extends StateNotifier<AppSurfaceStyle> {
  SurfaceStyleController(this._prefs) : super(_load(_prefs));

  static const String _key = 'naviwealth.theme.surface_style';
  final SharedPreferences _prefs;

  static AppSurfaceStyle _load(SharedPreferences p) =>
      AppSurfaceStyle.fromKey(p.getString(_key));

  Future<void> set(AppSurfaceStyle style) async {
    if (style == state) return;
    state = style;
    await _prefs.setString(_key, style.persistedKey);
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

/// User preference: locale override (en / zh / system).
///
/// When `null`, the app follows the system locale.
final localeProvider = StateNotifierProvider<LocaleController, Locale?>((ref) {
  return LocaleController(ref.watch(sharedPreferencesProvider));
});

class LocaleController extends StateNotifier<Locale?> {
  LocaleController(this._prefs) : super(_load(_prefs));

  static const String _key = 'naviwealth.locale';
  final SharedPreferences _prefs;

  static Locale? _load(SharedPreferences p) {
    final raw = p.getString(_key);
    if (raw == null) return null;
    return Locale(raw);
  }

  /// Cycle to the next supported locale: en → zh → system → en …
  void cycle() {
    final supported = <Locale>[const Locale('en'), const Locale('zh')];
    if (state == null) {
      // system → first supported
      set(supported.first);
    } else {
      final idx = supported.indexOf(state!);
      if (idx < 0 || idx >= supported.length - 1) {
        set(null); // back to system
      } else {
        set(supported[idx + 1]);
      }
    }
  }

  Future<void> set(Locale? locale) async {
    state = locale;
    if (locale == null) {
      await _prefs.remove(_key);
    } else {
      await _prefs.setString(_key, locale.languageCode);
    }
  }
}
