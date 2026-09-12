import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:naviwealth/core/auth/current_user.dart';
import 'package:naviwealth/core/auth/domain_opt_in_store.dart';
import 'package:naviwealth/core/auth/domain_scope.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/persistence/providers.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/health/data/health_metric_repository.dart';
import 'package:naviwealth/features/health/data/health_metric_write_service.dart';
import 'package:naviwealth/features/health/data/health_series_providers.dart';
import 'package:naviwealth/features/health/data/providers.dart' as health;
import 'package:naviwealth/features/health/domain/health_metric.dart';
import 'package:naviwealth/features/health/domain/health_metric_kind.dart';

import '../../../core/persistence/test_database.dart';
import '../../finance/data/repositories/_stub_stamper.dart';

class HealthTestFixture {
  HealthTestFixture._(this.db, this.repo);
  final AppDatabase db;
  final HealthMetricRepository repo;
  static final now = DateTime(2026, 9, 12, 12);
  static const owner = 'health-test';
  static Future<HealthTestFixture> create({bool populated = true}) async {
    final db = makeTestDatabase();
    await DomainOptInStore(db).write(DomainOptIns(const {DomainScope.health}));
    final repo = HealthMetricRepository(db: db, outbox: InMemoryOutboxStore());
    final result = HealthTestFixture._(db, repo);
    if (populated) {
      for (var i = 0; i < 60; i++) {
        final day = DateTime.utc(2026, 9, 12).subtract(Duration(days: i));
        await repo.upsertAll([
          result.metric(
            'garmin:steps:$i',
            HealthMetricKind.stepsDaily,
            day,
            i == 0 ? 3500 : 8000 + (i % 5) * 500,
          ),
          if (i != 3 && i != 4)
            result.metric(
              'garmin:hrv:$i',
              HealthMetricKind.hrvDaily,
              day,
              48 + (i % 7).toDouble(),
            ),
          result.metric(
            'garmin:rhr:$i',
            HealthMetricKind.rhrDaily,
            day,
            56 + (i % 3).toDouble(),
          ),
          result.metric(
            'garmin:sleep:$i',
            HealthMetricKind.sleepSession,
            DateTime(day.year, day.month, day.day - 1, 23).toUtc(),
            (7 + i % 2 * 0.5) * 3600,
          ),
        ]);
      }
      await result.writer.recordBodyMeasurement(
        kind: HealthMetricKind.weight,
        value: 72.5,
        capturedAt: DateTime.utc(2026, 9, 12, 12),
        note: 'Morning measurement',
      );
      await result.writer.recordBodyMeasurement(
        kind: HealthMetricKind.bodyFat,
        value: 0.185,
        capturedAt: DateTime.utc(2026, 9, 12, 12),
      );
    }
    return result;
  }

  HealthMetricWriteService get writer => HealthMetricWriteService(
    repository: repo,
    stamper: makeStubStamper(userId: owner),
  );
  HealthMetric metric(
    String id,
    HealthMetricKind kind,
    DateTime at,
    double value,
  ) => HealthMetric(
    id: id,
    kind: kind,
    capturedAt: at,
    value: value,
    unit: kind.defaultUnit,
    sync: SyncMeta(
      ownerUserId: owner,
      updatedAt: at,
      updatedByDevice: 'test',
      hlc: Hlc(
        wallMillis: at.millisecondsSinceEpoch,
        counter: 0,
        nodeId: 'test',
      ),
      deletedAt: null,
    ),
  );
  List<Override> get overrides => [
    appDatabaseProvider.overrideWith((_) async => db),
    currentUserIdProvider.overrideWithValue(() async => owner),
    healthClockProvider.overrideWithValue(() => now),
    health.healthMetricRepositoryProvider.overrideWith((_) async => repo),
    health.healthMetricWriteServiceProvider.overrideWith((_) async => writer),
    health.garminSyncControllerProvider.overrideWithBuild(
      (_, _) =>
          health.GarminConnected(lastSyncAt: now.toUtc(), totalMetrics: 240),
    ),
    health.healthSyncStatusProvider.overrideWithValue(null),
    health.healthPlatformStatusProvider.overrideWith(
      (_) async => const health.HealthPlatformStatus.unavailable(),
    ),
  ];
}
