import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/auth/current_user.dart';
import '../../../design_system/preferences/theme_preferences.dart';
import '../domain/health_metric_kind.dart';
import 'health_metric_source.dart';

class HealthPreferences {
  const HealthPreferences({this.sources = const {}, this.sleepGoalHours});
  final Map<HealthMetricKind, HealthMetricSource> sources;
  final double? sleepGoalHours;
}

/// Device-local, account-scoped view preferences. Source data stays intact.
class HealthPreferencesStore {
  HealthPreferencesStore(this._prefs, this.owner);
  final SharedPreferences _prefs;
  final String owner;
  String get _key => 'health.preferences.v1.${Uri.encodeComponent(owner)}';

  HealthPreferences read() {
    try {
      final decoded = jsonDecode(_prefs.getString(_key) ?? '{}');
      if (decoded is! Map<String, dynamic>) return const HealthPreferences();
      final sources = <HealthMetricKind, HealthMetricSource>{};
      if (decoded['sources'] case final Map<String, dynamic> values) {
        for (final entry in values.entries) {
          final kind = HealthMetricKindX.parse(entry.key);
          final source = healthMetricSourceFromId(
            entry.value is String ? entry.value as String : null,
          );
          if (kind != HealthMetricKind.unknown &&
              source != null &&
              source != HealthMetricSource.unknown) {
            sources[kind] = source;
          }
        }
      }
      final goal = (decoded['sleep_goal_hours'] as num?)?.toDouble();
      return HealthPreferences(
        sources: Map.unmodifiable(sources),
        sleepGoalHours: goal != null && goal.isFinite && goal >= 4 && goal <= 12
            ? goal
            : null,
      );
    } on Object {
      return const HealthPreferences();
    }
  }

  Future<void> setSource(
    HealthMetricKind kind,
    HealthMetricSource? source,
  ) async {
    final previous = read();
    final sources = {...previous.sources};
    if (source == null) {
      sources.remove(kind);
    } else {
      sources[kind] = source;
    }
    await _write(
      HealthPreferences(
        sources: sources,
        sleepGoalHours: previous.sleepGoalHours,
      ),
    );
  }

  Future<void> setSleepGoal(double? hours) async {
    if (hours != null && (!hours.isFinite || hours < 4 || hours > 12)) {
      throw ArgumentError.value(hours, 'hours');
    }
    await _write(
      HealthPreferences(sources: read().sources, sleepGoalHours: hours),
    );
  }

  Future<void> _write(HealthPreferences value) async {
    final saved = await _prefs.setString(
      _key,
      jsonEncode({
        'sources': {
          for (final entry in value.sources.entries)
            entry.key.wire: entry.value.id,
        },
        'sleep_goal_hours': value.sleepGoalHours,
      }),
    );
    if (!saved) throw StateError('Could not save health preferences.');
  }
}

final healthPreferencesStoreProvider = FutureProvider<HealthPreferencesStore>((
  ref,
) async {
  ref.watch(activeUserIdProvider);
  final owner = await ref.watch(currentUserIdProvider)();
  return HealthPreferencesStore(ref.watch(sharedPreferencesProvider), owner);
});

final healthPreferencesProvider = FutureProvider<HealthPreferences>(
  (ref) async =>
      (await ref.watch(healthPreferencesStoreProvider.future)).read(),
);
