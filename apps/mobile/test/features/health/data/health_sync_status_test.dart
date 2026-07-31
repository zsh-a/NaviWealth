import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/health/data/health_sync_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('health sync status survives a preferences round trip', () async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    final preferences = await SharedPreferences.getInstance();
    final store = HealthSyncStatusStore(preferences);

    await store.write(
      attemptedAt: DateTime.utc(2026, 7, 31, 8),
      completedAt: DateTime.utc(2026, 7, 31, 8, 0, 3),
      ok: true,
      totalFetched: 12,
      upserted: 8,
      unchanged: 4,
    );

    final restored = HealthSyncStatusStore(preferences).read();
    expect(restored, isNotNull);
    expect(restored!.attemptedAt, DateTime.utc(2026, 7, 31, 8));
    expect(restored.completedAt, DateTime.utc(2026, 7, 31, 8, 0, 3));
    expect(restored.ok, isTrue);
    expect(restored.totalFetched, 12);
    expect(restored.upserted, 8);
    expect(restored.unchanged, 4);
    expect(restored.lastSuccessAt, DateTime.utc(2026, 7, 31, 8, 0, 3));
    expect(restored.errorCode, isNull);
  });

  test('a failed attempt preserves the last successful refresh time', () async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    final preferences = await SharedPreferences.getInstance();
    final store = HealthSyncStatusStore(preferences);

    await store.write(
      attemptedAt: DateTime.utc(2026, 7, 31, 8),
      completedAt: DateTime.utc(2026, 7, 31, 8, 0, 3),
      ok: true,
      totalFetched: 4,
      upserted: 4,
      unchanged: 0,
    );
    await store.write(
      attemptedAt: DateTime.utc(2026, 8, 1, 8),
      completedAt: DateTime.utc(2026, 8, 1, 8, 0, 1),
      ok: false,
      totalFetched: 0,
      upserted: 0,
      unchanged: 0,
      errorCode: 'offline',
    );

    final restored = store.read();
    expect(restored!.ok, isFalse);
    expect(restored.lastSuccessAt, DateTime.utc(2026, 7, 31, 8, 0, 3));
  });

  test('malformed persisted status is ignored', () async {
    SharedPreferences.setMockInitialValues(const <String, Object>{
      kHealthSyncStatusKey: '{not-json',
    });
    final preferences = await SharedPreferences.getInstance();

    expect(HealthSyncStatusStore(preferences).read(), isNull);
  });
}
