import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/health/data/garmin/garmin_sync_status_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('checkpoints and retries are isolated by owner and region and survive restart', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = GarminSyncStatusStore(prefs);
    final now = DateTime.utc(2026, 9, 12);
    await store.saveCheckedDays('a', 'china', {'2026-09-11': now});
    await store.write(
      ownerUserId: 'a',
      region: 'china',
      lastAttemptAt: now,
      totalMetrics: 2,
      unchanged: 3,
      partial: true,
      errorCode: 'rate_limited',
      lastCheckedAt: now,
      nextRetryAt: now.add(const Duration(minutes: 30)),
      failureCount: 2,
    );
    final restored = GarminSyncStatusStore(prefs);
    expect(restored.checkedDays('a', 'china'), {'2026-09-11': now});
    expect(restored.checkedDays('a', 'global'), isEmpty);
    expect(restored.checkedDays('b', 'china'), isEmpty);
    final status = restored.read('a', region: 'china')!;
    expect(status.unchanged, 3);
    expect(status.partial, isTrue);
    expect(status.failureCount, 2);
    expect(status.nextRetryAt, now.add(const Duration(minutes: 30)));
    expect(restored.read('a', region: 'global'), isNull);
    await store.clear('a');
    expect(restored.checkedDays('a', 'china'), isEmpty);
    expect(restored.read('a', region: 'china'), isNull);
  });

  test(
    'legacy success does not fabricate a recent check or completed days',
    () async {
      SharedPreferences.setMockInitialValues({
        '$kGarminSyncStatusKeyPrefix.a':
            '{"last_attempt_at":"2026-09-12T00:00:00Z",'
            '"last_success_at":"2026-09-12T00:00:00Z","total_metrics":8}',
      });
      final store = GarminSyncStatusStore(
        await SharedPreferences.getInstance(),
      );
      expect(store.read('a', region: 'china')!.totalMetrics, 8);
      expect(store.read('a', region: 'china')!.lastCheckedAt, isNull);
      expect(store.checkedDays('a', 'china'), isEmpty);
    },
  );

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

  test('persists a failed attempt without losing the last success', () async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    final preferences = await SharedPreferences.getInstance();
    final store = GarminSyncStatusStore(preferences);

    await store.write(
      ownerUserId: 'owner-a',
      lastAttemptAt: DateTime.utc(2026, 7, 31, 8),
      lastSuccessAt: DateTime.utc(2026, 7, 31, 7, 0, 5),
      totalMetrics: 42,
    );
    await store.write(
      ownerUserId: 'owner-a',
      lastAttemptAt: DateTime.utc(2026, 7, 31, 9),
      lastSuccessAt: DateTime.utc(2026, 7, 31, 7, 0, 5),
      totalMetrics: 42,
      errorCode: 'auth_expired',
    );

    final restored = store.read('owner-a');
    expect(restored!.lastAttemptAt, DateTime.utc(2026, 7, 31, 9));
    expect(restored.lastSuccessAt, DateTime.utc(2026, 7, 31, 7, 0, 5));
    expect(restored.errorCode, 'auth_expired');
  });
}
