import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../design_system/preferences/theme_preferences.dart';
import '../domain/concentration_risk.dart';

/// Persisted concentration-risk thresholds. Stored locally via
/// SharedPreferences — these are per-device preferences, not synced.
final concentrationThresholdsProvider =
    StateNotifierProvider<
      ConcentrationThresholdsController,
      ConcentrationThresholds
    >((ref) {
      return ConcentrationThresholdsController(
        ref.watch(sharedPreferencesProvider),
      );
    });

class ConcentrationThresholdsController
    extends StateNotifier<ConcentrationThresholds> {
  ConcentrationThresholdsController(this._prefs) : super(_load(_prefs));

  static const _prefix = 'naviwealth.risk.threshold';
  static const _assetKey = '$_prefix.asset';
  static const _sectorKey = '$_prefix.sector';
  static const _regionKey = '$_prefix.region';
  static const _currencyKey = '$_prefix.currency';

  final SharedPreferences _prefs;

  static ConcentrationThresholds _load(SharedPreferences p) {
    final defaults = ConcentrationThresholds.defaults();
    return ConcentrationThresholds(
      assetWarning: p.getDouble(_assetKey) ?? defaults.assetWarning,
      sectorWarning: p.getDouble(_sectorKey) ?? defaults.sectorWarning,
      regionWarning: p.getDouble(_regionKey) ?? defaults.regionWarning,
      currencyWarning: p.getDouble(_currencyKey) ?? defaults.currencyWarning,
    );
  }

  Future<void> updateAsset(double value) async {
    state = state.copyWith(assetWarning: value);
    await _prefs.setDouble(_assetKey, value);
  }

  Future<void> updateSector(double value) async {
    state = state.copyWith(sectorWarning: value);
    await _prefs.setDouble(_sectorKey, value);
  }

  Future<void> updateRegion(double value) async {
    state = state.copyWith(regionWarning: value);
    await _prefs.setDouble(_regionKey, value);
  }

  Future<void> updateCurrency(double value) async {
    state = state.copyWith(currencyWarning: value);
    await _prefs.setDouble(_currencyKey, value);
  }

  Future<void> resetToDefaults() async {
    final defaults = ConcentrationThresholds.defaults();
    state = defaults;
    await Future.wait([
      _prefs.remove(_assetKey),
      _prefs.remove(_sectorKey),
      _prefs.remove(_regionKey),
      _prefs.remove(_currencyKey),
    ]);
  }

  /// Replace all four warning levels in one shot. Used by the risk
  /// appetite SSOT to snap thresholds onto the matching preset when
  /// the user picks Conservative / Moderate / Aggressive — saves a
  /// round trip per-field and a noisy four-emission state thrash.
  Future<void> applyAll(ConcentrationThresholds next) async {
    if (next.assetWarning == state.assetWarning &&
        next.sectorWarning == state.sectorWarning &&
        next.regionWarning == state.regionWarning &&
        next.currencyWarning == state.currencyWarning) {
      return;
    }
    state = next;
    await Future.wait<void>([
      _prefs.setDouble(_assetKey, next.assetWarning),
      _prefs.setDouble(_sectorKey, next.sectorWarning),
      _prefs.setDouble(_regionKey, next.regionWarning),
      _prefs.setDouble(_currencyKey, next.currencyWarning),
    ]);
  }
}
