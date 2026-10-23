import 'package:flutter_riverpod/legacy.dart';
import 'package:naviwealth/features/finance/analytics/domain/concentration_risk.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../design_system/preferences/theme_preferences.dart';

/// Finance-owned investment risk preference shared by allocation, settings,
/// and Finance AI context. Custom weights remain an explicit custom choice.
enum RiskAppetite { conservative, moderate, aggressive, custom }

extension RiskAppetiteX on RiskAppetite {
  /// Wire-stable name used in SharedPreferences. Decoupled from the
  /// `enum.name` so future renames don't break persisted values.
  String get storageKey => switch (this) {
    RiskAppetite.conservative => 'conservative',
    RiskAppetite.moderate => 'moderate',
    RiskAppetite.aggressive => 'aggressive',
    RiskAppetite.custom => 'custom',
  };
}

RiskAppetite _parse(String? raw) => switch (raw) {
  'conservative' => RiskAppetite.conservative,
  'moderate' => RiskAppetite.moderate,
  'aggressive' => RiskAppetite.aggressive,
  'custom' => RiskAppetite.custom,
  _ => RiskAppetite.moderate,
};

/// Persisted risk appetite. Defaults to [RiskAppetite.moderate] so a
/// fresh install lands on the "balanced" rebalance preset — the same
/// default the rebalance feature has shipped with.
final riskAppetiteProvider =
    StateNotifierProvider<RiskAppetiteController, RiskAppetite>((ref) {
      return RiskAppetiteController(ref.watch(sharedPreferencesProvider));
    });

/// Map a [RiskAppetite] onto the concentration-alert thresholds that
/// best fit it. Conservative investors want tighter alerts (smaller
/// numbers ⇒ fire earlier); aggressive investors want looser ones.
/// `custom` shares the moderate preset since the appetite enum's
/// `custom` flag is about hand-edited *allocation*, not about
/// hand-edited alert sensitivity — users who want custom alerts go
/// edit them directly on the thresholds page.
ConcentrationThresholds concentrationThresholdsForAppetite(
  RiskAppetite appetite,
) => switch (appetite) {
  RiskAppetite.conservative => const ConcentrationThresholds(
    assetWarning: 0.15,
    sectorWarning: 0.25,
    regionWarning: 0.50,
    currencyWarning: 0.40,
  ),
  RiskAppetite.moderate || RiskAppetite.custom =>
    // ConcentrationThresholds.defaults() returns these exact values —
    // we duplicate them here as a const so the table reads in one
    // place. Keep in sync if defaults shift.
    const ConcentrationThresholds(
      assetWarning: 0.20,
      sectorWarning: 0.35,
      regionWarning: 0.60,
      currencyWarning: 0.50,
    ),
  RiskAppetite.aggressive => const ConcentrationThresholds(
    assetWarning: 0.30,
    sectorWarning: 0.50,
    regionWarning: 0.75,
    currencyWarning: 0.65,
  ),
};

/// True when [t] matches any of the appetite-aligned threshold presets
/// within float tolerance. The Settings UI uses this to decide whether
/// the user has hand-customised thresholds: when they haven't, we
/// snap the four levels to the new appetite's preset on appetite
/// change so the "auto-tuned by your risk appetite" subtitle isn't a
/// lie.
bool isAtAnyAppetitePreset(ConcentrationThresholds t) {
  const eps = 1e-6;
  bool eq(double a, double b) => (a - b).abs() < eps;
  for (final candidate in RiskAppetite.values) {
    final preset = concentrationThresholdsForAppetite(candidate);
    if (eq(t.assetWarning, preset.assetWarning) &&
        eq(t.sectorWarning, preset.sectorWarning) &&
        eq(t.regionWarning, preset.regionWarning) &&
        eq(t.currencyWarning, preset.currencyWarning)) {
      return true;
    }
  }
  return false;
}

class RiskAppetiteController extends StateNotifier<RiskAppetite> {
  RiskAppetiteController(this._prefs) : super(_load(_prefs));

  static const String _key = 'naviwealth.preferences.risk_appetite';

  final SharedPreferences _prefs;

  static RiskAppetite _load(SharedPreferences p) => _parse(p.getString(_key));

  Future<void> set(RiskAppetite next) async {
    if (next == state) return;
    state = next;
    await _prefs.setString(_key, next.storageKey);
  }
}
