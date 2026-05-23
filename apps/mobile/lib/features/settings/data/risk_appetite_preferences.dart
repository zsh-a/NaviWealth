import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/ai/contracts/base_context.dart' as ai
    show RiskPreference;
import '../../../design_system/preferences/theme_preferences.dart';

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
