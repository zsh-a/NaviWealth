import 'dart:convert';

import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../design_system/preferences/theme_preferences.dart';
import '../domain/fire_plan.dart';

/// SharedPreferences-backed storage for the FIRE-OS-only extras: the
/// safe-withdrawal rate, the cash-bucket month target, the lifestyle
/// posture, named reserves and the risk-settings tuning.
///
/// The shared planning fields (`targetAmount`, `monthlyExpenses`,
/// `monthlySurplus`, `inflationRate`) continue to live on
/// `FireGoalController` so the existing dashboard projection and golden
/// tests stay bit-compatible — see `fire_providers.dart` for the
/// composer that snaps the two halves together into a [FirePlan].
///
/// Per `docs/roadmap-fire-os.md` §7.1 the MVP intentionally keeps these
/// out of the sync protocol; Phase 6 will migrate to a `fire_plans` /
/// `fire_bucket_rules` Drift table set.
final firePlanExtrasProvider =
    StateNotifierProvider<FirePlanExtrasController, FirePlanExtras>((ref) {
      return FirePlanExtrasController(ref.watch(sharedPreferencesProvider));
    });

/// The slice of [FirePlan] that does *not* overlap with the legacy
/// `FireGoal` storage. Persisted as a small set of typed keys + two
/// JSON blobs (reserves and risk settings).
class FirePlanExtras {
  const FirePlanExtras({
    required this.safeWithdrawalRate,
    required this.targetCashBucketMonths,
    required this.lifestyleMode,
    required this.reserves,
    required this.riskSettings,
  });

  factory FirePlanExtras.defaults() => const FirePlanExtras(
    safeWithdrawalRate: FirePlan.defaultSafeWithdrawalRate,
    targetCashBucketMonths: FirePlan.defaultCashBucketMonths,
    lifestyleMode: FireLifestyleMode.standard,
    reserves: <FireReserve>[],
    riskSettings: FireRiskSettings(),
  );

  final double safeWithdrawalRate;
  final int targetCashBucketMonths;
  final FireLifestyleMode lifestyleMode;
  final List<FireReserve> reserves;
  final FireRiskSettings riskSettings;

  FirePlanExtras copyWith({
    double? safeWithdrawalRate,
    int? targetCashBucketMonths,
    FireLifestyleMode? lifestyleMode,
    List<FireReserve>? reserves,
    FireRiskSettings? riskSettings,
  }) {
    return FirePlanExtras(
      safeWithdrawalRate: safeWithdrawalRate ?? this.safeWithdrawalRate,
      targetCashBucketMonths:
          targetCashBucketMonths ?? this.targetCashBucketMonths,
      lifestyleMode: lifestyleMode ?? this.lifestyleMode,
      reserves: reserves ?? this.reserves,
      riskSettings: riskSettings ?? this.riskSettings,
    );
  }
}

class FirePlanExtrasController extends StateNotifier<FirePlanExtras> {
  FirePlanExtrasController(this._prefs) : super(_load(_prefs));

  static const _kSwr = 'naviwealth.fire.swr';
  static const _kCashMonths = 'naviwealth.fire.cash_bucket_months';
  static const _kLifestyle = 'naviwealth.fire.lifestyle_mode';
  static const _kReserves = 'naviwealth.fire.reserves_json';
  static const _kRiskSettings = 'naviwealth.fire.risk_settings_json';

  final SharedPreferences _prefs;

  static FirePlanExtras _load(SharedPreferences p) {
    return FirePlanExtras(
      safeWithdrawalRate:
          p.getDouble(_kSwr) ?? FirePlan.defaultSafeWithdrawalRate,
      targetCashBucketMonths:
          p.getInt(_kCashMonths) ?? FirePlan.defaultCashBucketMonths,
      lifestyleMode: _readEnum(
        p.getString(_kLifestyle),
        FireLifestyleMode.values,
        FireLifestyleMode.standard,
      ),
      reserves: _decodeReserves(p.getString(_kReserves)),
      riskSettings: _decodeRiskSettings(p.getString(_kRiskSettings)),
    );
  }

  Future<void> save(FirePlanExtras extras) async {
    state = extras;
    await Future.wait<void>(<Future<void>>[
      _prefs.setDouble(_kSwr, extras.safeWithdrawalRate),
      _prefs.setInt(_kCashMonths, extras.targetCashBucketMonths),
      _prefs.setString(_kLifestyle, extras.lifestyleMode.name),
      _prefs.setString(
        _kReserves,
        jsonEncode(extras.reserves.map((r) => r.toJson()).toList()),
      ),
      _prefs.setString(_kRiskSettings, jsonEncode(extras.riskSettings.toJson())),
    ]);
  }

  /// Wipe the extras back to defaults. Used by the "start over" CTA in
  /// settings and by tests.
  Future<void> clear() async {
    state = FirePlanExtras.defaults();
    await Future.wait<void>(<Future<void>>[
      _prefs.remove(_kSwr),
      _prefs.remove(_kCashMonths),
      _prefs.remove(_kLifestyle),
      _prefs.remove(_kReserves),
      _prefs.remove(_kRiskSettings),
    ]);
  }

  static FireLifestyleMode _readEnum(
    String? raw,
    List<FireLifestyleMode> values,
    FireLifestyleMode fallback,
  ) {
    if (raw == null) return fallback;
    for (final v in values) {
      if (v.name == raw) return v;
    }
    return fallback;
  }

  static List<FireReserve> _decodeReserves(String? raw) {
    if (raw == null || raw.isEmpty) return const <FireReserve>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <FireReserve>[];
      return decoded.whereType<Map<dynamic, dynamic>>().map((m) {
        final coerced = Map<String, Object?>.from(m);
        return FireReserve.fromJson(coerced, _bestEffortCurrency(coerced));
      }).toList(growable: false);
    } on FormatException {
      return const <FireReserve>[];
    }
  }

  static String _bestEffortCurrency(Map<String, Object?> m) {
    final c = m['currency'];
    if (c is String && c.trim().isNotEmpty) return c;
    return 'CNY';
  }

  static FireRiskSettings _decodeRiskSettings(String? raw) {
    if (raw == null || raw.isEmpty) return const FireRiskSettings();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const FireRiskSettings();
      return FireRiskSettings.fromJson(Map<String, Object?>.from(decoded));
    } on FormatException {
      return const FireRiskSettings();
    }
  }
}
