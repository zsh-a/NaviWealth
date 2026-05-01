import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../design_system/preferences/theme_preferences.dart';
import '../domain/fire_goal.dart';

/// SharedPreferences-backed storage for the FIRE goal.
///
/// FIRE goal is a personal planning input — not a synced piece of portfolio
/// state — so it lives in `SharedPreferences` next to the other UI prefs
/// (`theme_preferences.dart`) rather than the Drift schema. That also keeps
/// the goal local-only by construction; the user's target net worth is the
/// kind of thing they'd rather not see roundtripped through the sync pipe.
final fireGoalProvider =
    StateNotifierProvider<FireGoalController, FireGoal>((ref) {
  return FireGoalController(ref.watch(sharedPreferencesProvider));
});

/// Persistence layer for [FireGoal]. The four fields are kept as separate
/// keys (rather than a single JSON blob) so a future migration that adds
/// e.g. a `goalDate` field can roll forward without breaking older
/// installs that still write the old shape.
class FireGoalController extends StateNotifier<FireGoal> {
  FireGoalController(this._prefs) : super(_load(_prefs));

  static const _kTarget = 'naviwealth.fire.target_amount';
  static const _kMonthlyExpenses = 'naviwealth.fire.monthly_expenses';
  static const _kMonthlySurplus = 'naviwealth.fire.monthly_surplus';
  static const _kInflation = 'naviwealth.fire.inflation_rate';

  final SharedPreferences _prefs;

  static FireGoal _load(SharedPreferences p) {
    return FireGoal(
      targetAmount: _readDecimal(p, _kTarget) ?? Decimal.zero,
      monthlyExpenses: _readDecimal(p, _kMonthlyExpenses) ?? Decimal.zero,
      monthlySurplus: _readDecimal(p, _kMonthlySurplus) ?? Decimal.zero,
      inflationRate:
          p.getDouble(_kInflation) ?? FireGoal.defaultInflationRate,
    );
  }

  Future<void> save(FireGoal goal) async {
    state = goal;
    await Future.wait<void>(<Future<void>>[
      _writeDecimal(_kTarget, goal.targetAmount),
      _writeDecimal(_kMonthlyExpenses, goal.monthlyExpenses),
      _writeDecimal(_kMonthlySurplus, goal.monthlySurplus),
      _prefs.setDouble(_kInflation, goal.inflationRate),
    ]);
  }

  /// Wipe the goal back to the unconfigured state. Useful for "start over"
  /// flows and for tests.
  Future<void> clear() async {
    state = FireGoal.unset();
    await Future.wait<void>(<Future<void>>[
      _prefs.remove(_kTarget),
      _prefs.remove(_kMonthlyExpenses),
      _prefs.remove(_kMonthlySurplus),
      _prefs.remove(_kInflation),
    ]);
  }

  Future<void> _writeDecimal(String key, Decimal value) {
    return _prefs.setString(key, value.toString());
  }

  static Decimal? _readDecimal(SharedPreferences p, String key) {
    final raw = p.getString(key);
    if (raw == null || raw.isEmpty) return null;
    try {
      return Decimal.parse(raw);
    } on FormatException {
      // Corrupt write from an older build — fall back to "unset" rather
      // than crashing the dashboard. The next save overwrites the bad value.
      return null;
    }
  }
}
