import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/health/data/garmin/garmin_sync_status_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('Garmin sync status is persisted per owner', () async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    final preferences = await SharedPreferences.getInstance();
    final store = GarminSyncStatusStore(preferences);

    await store.write(
      ownerUserId: 'owner-a',
      lastAttemptAt: DateTime.utc(2026, 7, 31, 8),
      lastSuccessAt: DateTime.utc(2026, 7, 31, 8, 0, 5),
      totalMetrics: 42,
    );

    final restored = store.read('owner-a');
    expect(restored, isNotNull);
    expect(restored!.lastAttemptAt, DateTime.utc(2026, 7, 31, 8));
    expect(restored.lastSuccessAt, DateTime.utc(2026, 7, 31, 8, 0, 5));
    expect(restored.totalMetrics, 42);
    expect(store.read('owner-b'), isNull);
  });

  test('clearing one owner keeps other owners intact', () async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    final preferences = await SharedPreferences.getInstance();
    final store = GarminSyncStatusStore(preferences);

    for (final owner in <String>['owner-a', 'owner-b']) {
      await store.write(
        ownerUserId: owner,
        lastAttemptAt: DateTime.utc(2026, 7, 31),
        lastSuccessAt: DateTime.utc(2026, 7, 31),
        totalMetrics: 1,
      );
    }

    await store.clear('owner-a');
    expect(store.read('owner-a'), isNull);
    expect(store.read('owner-b'), isNotNull);
  });
}
