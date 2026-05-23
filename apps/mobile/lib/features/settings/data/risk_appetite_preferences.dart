import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/ai/contracts/base_context.dart' as ai
    show RiskPreference;
import '../../../design_system/preferences/theme_preferences.dart';
import '../../analytics/domain/concentration_risk.dart';

/// User-declared appetite for investment risk. Single source of truth
/// for everything downstream that needs a "how aggressive is this user"
/// signal:
///
///  - the Rebalance feature derives its [AllocationSchemePreset]
///    one-to-one from this value;
///  - the AI ContextPack passes this through (as a 3-value wire enum)
///    so on-device LLM advice can take the user's tolerance into
///    account;
///  - the Settings UI lets the user set it explicitly with a single
///    chip row — no more digging into Rebalance to "set risk".
///
/// Why a 4-value enum (vs. the existing 3-value wire enum in
/// `core/ai/contracts/base_context.dart`)? UX needs a [custom] state
/// for "I edited my own target weights, don't snap me to a preset" —
/// that's a UI concern that doesn't carry across the AI wire. The
/// [RiskAppetiteX.toWire] mapper collapses `custom` → `moderate` when
/// emitted into a [ContextPack], keeping the wire contract stable.
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

  /// Project to the 3-value AI wire enum. `custom` falls back to
  /// `moderate` — the AI side has no notion of "user-edited weights",
  /// it just needs a coarse risk dial.
  ai.RiskPreference toWire() => switch (this) {
    RiskAppetite.conservative => ai.RiskPreference.conservative,
    RiskAppetite.moderate || RiskAppetite.custom => ai.RiskPreference.moderate,
    RiskAppetite.aggressive => ai.RiskPreference.aggressive,
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
