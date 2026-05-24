import 'dart:convert';

import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../design_system/preferences/theme_preferences.dart';
import '../domain/fire_bucket.dart';

/// SharedPreferences-backed storage for user-declared bucket mappings.
///
/// Per `docs/roadmap-fire-os.md` §7.1 the MVP stays out of the sync
/// protocol. The Phase-6 migration path moves these rows into a
/// `fire_bucket_rules` Drift table with the same JSON shape so a
/// one-shot exporter can ferry them across.
final fireBucketRulesProvider =
    StateNotifierProvider<FireBucketRulesController, List<FireBucketRule>>(
      (ref) => FireBucketRulesController(ref.watch(sharedPreferencesProvider)),
    );

class FireBucketRulesController extends StateNotifier<List<FireBucketRule>> {
  FireBucketRulesController(this._prefs) : super(_load(_prefs));

  static const _kRules = 'naviwealth.fire.bucket_rules_json';
  final SharedPreferences _prefs;

  static List<FireBucketRule> _load(SharedPreferences p) {
    final raw = p.getString(_kRules);
    if (raw == null || raw.isEmpty) return const <FireBucketRule>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <FireBucketRule>[];
      return decoded
          .whereType<Map<dynamic, dynamic>>()
          .map((m) => FireBucketRule.fromJson(Map<String, Object?>.from(m)))
          .toList(growable: false);
    } on FormatException {
      return const <FireBucketRule>[];
    }
  }

  Future<void> save(List<FireBucketRule> rules) async {
    state = List.unmodifiable(rules);
    await _prefs.setString(
      _kRules,
      jsonEncode(rules.map((r) => r.toJson()).toList()),
    );
  }

  /// Add or replace a rule. The rule's id keys the replacement.
  Future<void> upsert(FireBucketRule rule) async {
    final next = <FireBucketRule>[
      for (final existing in state)
        if (existing.id != rule.id) existing,
      rule,
    ];
    await save(next);
  }

  Future<void> remove(String ruleId) async {
    final next = state.where((r) => r.id != ruleId).toList();
    await save(next);
  }

  Future<void> clear() async {
    state = const <FireBucketRule>[];
    await _prefs.remove(_kRules);
  }
}
