import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../design_system/preferences/theme_preferences.dart';

/// Default base currency when none is persisted yet. Matches the legacy
/// hardcoded value the dashboard used before FIR-73 surfaced the setting.
const String kDefaultBaseCurrency = 'CNY';

/// User preference: base currency the dashboard, allocation pie, trend
/// chart, FIRE projections and other reports render totals in.
///
/// Persisted in [SharedPreferences] alongside other UI preferences so it
/// resolves synchronously on first build, before any async repository
/// hydration. Eventually the canonical setting lives in the synced
/// `Settings` table (FIR-21); this controller reads from / writes to that
/// row once the repository ships, but we keep [SharedPreferences] as the
/// fast-path read so a cold start never paints with the wrong currency.
final baseCurrencyProvider =
    StateNotifierProvider<BaseCurrencyController, String>((ref) {
  return BaseCurrencyController(ref.watch(sharedPreferencesProvider));
});

class BaseCurrencyController extends StateNotifier<String> {
  BaseCurrencyController(this._prefs) : super(_load(_prefs));

  static const String _key = 'naviwealth.settings.base_currency';
  final SharedPreferences _prefs;

  static String _load(SharedPreferences p) {
    final raw = p.getString(_key);
    if (raw == null || raw.isEmpty) return kDefaultBaseCurrency;
    return raw.trim().toUpperCase();
  }

  Future<void> set(String code) async {
    final normalized = code.trim().toUpperCase();
    if (normalized.isEmpty || normalized == state) return;
    state = normalized;
    await _prefs.setString(_key, normalized);
  }
}
