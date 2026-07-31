import 'dart:convert';

import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../design_system/preferences/theme_preferences.dart';

const String kExecutionDailyFocusKey = 'lifeos.execution.daily_focus.v1';

final executionDailyFocusProvider =
    StateNotifierProvider<ExecutionDailyFocusController, List<String>>((ref) {
      SharedPreferences? preferences;
      try {
        preferences = ref.watch(sharedPreferencesProvider);
      } on Object {
        // Focus remains usable in isolated surfaces without app bootstrap.
      }
      return ExecutionDailyFocusController(preferences);
    });

final class ExecutionDailyFocusController extends StateNotifier<List<String>> {
  ExecutionDailyFocusController(this._preferences)
    : super(_preferences == null ? const <String>[] : _readToday(_preferences));

  final SharedPreferences? _preferences;

  Future<void> toggle(String actionId) async {
    final next = state.contains(actionId)
        ? state.where((id) => id != actionId).toList(growable: false)
        : state.length >= 3
        ? <String>[...state.skip(1), actionId]
        : <String>[...state, actionId];
    await set(next);
  }

  Future<void> set(Iterable<String> ids) async {
    final normalized = ids
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .take(3)
        .toList(growable: false);
    state = normalized;
    await _preferences?.setString(
      kExecutionDailyFocusKey,
      jsonEncode(<String, Object?>{
        'day': _localDayKey(DateTime.now()),
        'action_ids': normalized,
      }),
    );
  }

  Future<void> adoptRecommendedIfEmpty(Iterable<String> ids) async {
    if (state.isNotEmpty) return;
    await set(ids);
  }

  static List<String> _readToday(SharedPreferences preferences) {
    final encoded = preferences.getString(kExecutionDailyFocusKey);
    if (encoded == null) return const <String>[];
    try {
      final json = jsonDecode(encoded);
      if (json is! Map<String, Object?> ||
          json['day'] != _localDayKey(DateTime.now())) {
        return const <String>[];
      }
      final ids = json['action_ids'];
      if (ids is! List) return const <String>[];
      return ids.whereType<String>().take(3).toList(growable: false);
    } on Object {
      return const <String>[];
    }
  }
}

String _localDayKey(DateTime value) {
  final local = value.toLocal();
  return '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';
}
