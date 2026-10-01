import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/health/data/health_metric_source.dart';
import 'package:naviwealth/features/health/data/health_preferences.dart';
import 'package:naviwealth/features/health/domain/health_metric_kind.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'source and sleep goals are account-scoped and survive restart',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = HealthPreferencesStore(prefs, 'alice');
      await store.setSource(
        HealthMetricKind.hrvDaily,
        HealthMetricSource.healthKit,
      );
      await store.setSleepGoal(8);
      final restored = HealthPreferencesStore(prefs, 'alice').read();
      expect(
        restored.sources[HealthMetricKind.hrvDaily],
        HealthMetricSource.healthKit,
      );
      expect(restored.sleepGoalHours, 8);
      expect(HealthPreferencesStore(prefs, 'bob').read().sources, isEmpty);
      expect(
        HealthPreferencesStore(prefs, 'bob').read().sleepGoalHours,
        isNull,
      );
      await store.setSource(HealthMetricKind.hrvDaily, null);
      await store.setSleepGoal(null);
      expect(store.read().sources, isEmpty);
      expect(store.read().sleepGoalHours, isNull);
    },
  );
  test('invalid goals never overwrite the previous preference', () async {
    SharedPreferences.setMockInitialValues({});
    final store = HealthPreferencesStore(
      await SharedPreferences.getInstance(),
      'user',
    );
    await store.setSleepGoal(8);
    await expectLater(store.setSleepGoal(double.nan), throwsArgumentError);
    expect(store.read().sleepGoalHours, 8);
  });
}
