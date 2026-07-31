import 'dart:convert';

import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/auth/current_user.dart';
import '../../../design_system/preferences/theme_preferences.dart';

String executionDailyFocusKey(String ownerUserId) =>
    'lifeos.execution.$ownerUserId.daily_focus.v2';

final executionDailyFocusProvider =
    StateNotifierProvider<ExecutionDailyFocusController, List<String>>((ref) {
      SharedPreferences? preferences;
      try {
        preferences = ref.watch(sharedPreferencesProvider);
      } on Object {
        // Focus remains usable in isolated surfaces without app bootstrap.
      }
      final ownerUserId = ref.watch(activeUserIdProvider) ?? kLocalOnlyUserId;
      return ExecutionDailyFocusController(preferences, ownerUserId);
    });

final class ExecutionDailyFocusController extends StateNotifier<List<String>> {
  ExecutionDailyFocusController(this._preferences, this._ownerUserId)
    : super(
        _preferences == null
            ? const <String>[]
            : _readToday(_preferences, _ownerUserId),
      );

  final SharedPreferences? _preferences;
  final String _ownerUserId;

  /// Returns false instead of silently evicting a selected action when full.
  Future<bool> toggle(String actionId) async {
    if (!state.contains(actionId) && state.length >= 3) return false;
    final next = state.contains(actionId)
        ? state.where((id) => id != actionId).toList(growable: false)
        : <String>[...state, actionId];
    await set(next);
    return true;
  }

  Future<void> replace(String removedId, String addedId) async {
    await set([for (final id in state) id == removedId ? addedId : id]);
  }

  Future<void> move(String actionId, int offset) async {
    final from = state.indexOf(actionId);
    if (from < 0) return;
    final to = (from + offset).clamp(0, state.length - 1);
    if (from == to) return;
    final next = List<String>.of(state);
    final item = next.removeAt(from);
    next.insert(to, item);
    await set(next);
  }

  Future<void> retainExisting(Iterable<String> ids) async {
    final existing = ids.toSet();
    final next = state.where(existing.contains).toList(growable: false);
    if (next.length != state.length) await set(next);
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
      executionDailyFocusKey(_ownerUserId),
      jsonEncode(<String, Object?>{
        'day': _localDayKey(DateTime.now()),
        'action_ids': normalized,
      }),
    );
  }

  static List<String> _readToday(
    SharedPreferences preferences,
    String ownerUserId,
  ) {
    final encoded = preferences.getString(executionDailyFocusKey(ownerUserId));
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
