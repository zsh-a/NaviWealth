import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../design_system/preferences/theme_preferences.dart';
import '../../home/data/dashboard_providers.dart';
import '../domain/allocation_schemes.dart';
import '../domain/rebalance_engine.dart';
import '../domain/rebalance_models.dart';

const _kTargetAllocationKey = 'naviwealth.rebalance.target_allocation';
const _kSelectedSchemeKey = 'naviwealth.rebalance.selected_scheme';
const _kWarningThresholdKey = 'naviwealth.rebalance.warning_threshold';
const _kCriticalThresholdKey = 'naviwealth.rebalance.critical_threshold';

/// The rebalance engine instance. Thresholds are user-configurable via
/// [warningThresholdProvider] / [criticalThresholdProvider].
final rebalanceEngineProvider = Provider<RebalanceEngine>((ref) {
  final warning = ref.watch(warningThresholdProvider);
  final critical = ref.watch(criticalThresholdProvider);
  return RebalanceEngine(
    warningThreshold: warning,
    criticalThreshold: critical,
  );
});

/// User-selected allocation scheme preset. Defaults to [balanced].
final selectedSchemeProvider =
    StateNotifierProvider<SelectedSchemeController, AllocationSchemePreset>(
  (ref) {
    return SelectedSchemeController(ref.watch(sharedPreferencesProvider));
  },
);

class SelectedSchemeController extends StateNotifier<AllocationSchemePreset> {
  SelectedSchemeController(this._prefs) : super(_load(_prefs));

  final SharedPreferences _prefs;

  static AllocationSchemePreset _load(SharedPreferences p) {
    final raw = p.getString(_kSelectedSchemeKey);
    return AllocationSchemePreset.values.firstWhere(
      (e) => e.name == raw,
      orElse: () => AllocationSchemePreset.balanced,
    );
  }

  Future<void> select(AllocationSchemePreset preset) async {
    state = preset;
    await _prefs.setString(_kSelectedSchemeKey, preset.name);
  }
}

/// User's target allocation weights. When the scheme changes, this resets
/// to the preset's default weights unless the user has customised it.
final targetAllocationProvider =
    StateNotifierProvider<TargetAllocationController, TargetAllocation>(
  (ref) {
    final prefs = ref.watch(sharedPreferencesProvider);
    final scheme = ref.watch(selectedSchemeProvider);
    return TargetAllocationController(prefs, scheme);
  },
);

class TargetAllocationController extends StateNotifier<TargetAllocation> {
  TargetAllocationController(this._prefs, this._scheme)
      : super(_load(_prefs, _scheme));

  final SharedPreferences _prefs;
  final AllocationSchemePreset _scheme;

  static TargetAllocation _load(
    SharedPreferences p,
    AllocationSchemePreset scheme,
  ) {
    final raw = p.getString(_kTargetAllocationKey);
    if (raw != null) {
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        return TargetAllocation.fromJson(map);
      } catch (_) {
        // Fall through to preset.
      }
    }
    return allocationScheme(scheme);
  }

  Future<void> update(TargetAllocation allocation) async {
    state = allocation;
    await _prefs.setString(_kTargetAllocationKey, jsonEncode(allocation.toJson()));
  }

  /// Reset to the current scheme's default weights.
  Future<void> resetToScheme() async {
    final preset = allocationScheme(_scheme);
    state = preset;
    await _prefs.setString(_kTargetAllocationKey, jsonEncode(preset.toJson()));
  }
}

/// Warning threshold (default 5%).
final warningThresholdProvider =
    StateNotifierProvider<ThresholdController, double>((ref) {
  return ThresholdController(
    ref.watch(sharedPreferencesProvider),
    key: _kWarningThresholdKey,
    defaultValue: 0.05,
  );
});

/// Critical threshold (default 10%).
final criticalThresholdProvider =
    StateNotifierProvider<ThresholdController, double>((ref) {
  return ThresholdController(
    ref.watch(sharedPreferencesProvider),
    key: _kCriticalThresholdKey,
    defaultValue: 0.10,
  );
});

class ThresholdController extends StateNotifier<double> {
  ThresholdController(this._prefs, {required this.key, required this.defaultValue})
      : super(_prefs.getDouble(key) ?? defaultValue);

  final SharedPreferences _prefs;
  final String key;
  final double defaultValue;

  Future<void> set(double value) async {
    state = value;
    await _prefs.setDouble(key, value);
  }
}

/// The computed rebalance plan. Reactively recomputes when the dashboard
/// snapshot or target allocation changes.
final rebalancePlanProvider = Provider<RebalancePlan?>((ref) {
  final snapshotAsync = ref.watch(dashboardSnapshotProvider);
  final target = ref.watch(targetAllocationProvider);
  final engine = ref.watch(rebalanceEngineProvider);

  final snapshot = snapshotAsync.value;
  if (snapshot == null || snapshot.isEmpty) return null;

  return engine.compute(snapshot: snapshot, target: target);
});
