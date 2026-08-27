import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/auth/current_user.dart';
import 'package:naviwealth/core/auth/domain_scope.dart';
import 'package:naviwealth/core/auth/providers.dart' as auth;
import 'package:naviwealth/core/persistence/providers.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/outbox_provider.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/health/data/health_platform_adapter.dart';
import 'package:naviwealth/features/health/data/providers.dart';
import 'package:naviwealth/features/health/domain/health_metric.dart';
import 'package:naviwealth/features/health/domain/health_metric_kind.dart';

import '../../../core/persistence/test_database.dart';

const _owner = 'health-source-owner';

class _FakePlatformAdapter implements HealthPlatformAdapter {
  _FakePlatformAdapter({required this.available, required this.permissions});

  final bool available;
  final bool permissions;

  @override
  Future<bool> hasPermissions() async => permissions;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<bool> requestPermissions() async => permissions;

  @override
  Future<HealthPlatformSnapshot> fetchRange({
    required DateTime from,
    required DateTime to,
  }) async => const HealthPlatformSnapshot.empty();
}

HealthMetric _metric({
  required String id,
  required HealthMetricKind kind,
  required DateTime capturedAt,
}) => HealthMetric(
  id: id,
  capturedAt: capturedAt,
  kind: kind,
  value: 1,
  unit: kind.defaultUnit,
  sync: SyncMeta(
    ownerUserId: _owner,
    updatedAt: capturedAt,
    updatedByDevice: 'test-device',
    hlc: Hlc(
      wallMillis: capturedAt.millisecondsSinceEpoch,
      counter: 0,
      nodeId: 'test-device',
    ),
    deletedAt: null,
  ),
);

void main() {
  test(
    'platform status distinguishes unavailable, permission, and ready',
    () async {
      for (final scenario
          in <
            ({
              bool available,
              bool permissions,
              bool Function(HealthPlatformStatus) matches,
            })
          >[
            (
              available: false,
              permissions: false,
              matches: (status) => !status.available,
            ),
            (
              available: true,
              permissions: false,
              matches: (status) => status.needsPermission,
            ),
            (
              available: true,
              permissions: true,
              matches: (status) => status.ready,
            ),
          ]) {
        final container = ProviderContainer(
          overrides: [
            healthPlatformAdapterProvider.overrideWithValue(
              _FakePlatformAdapter(
                available: scenario.available,
                permissions: scenario.permissions,
              ),
            ),
          ],
        );
        addTearDown(container.dispose);

        final status = await container.read(
          healthPlatformStatusProvider.future,
        );
        expect(scenario.matches(status), isTrue);
      }
    },
  );

  test(
    'latest source data is grouped without losing disconnected data',
    () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final outbox = InMemoryOutboxStore();
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWith((ref) async => db),
          outboxStoreProvider.overrideWith((ref) async => outbox),
          currentUserIdProvider.overrideWithValue(() async => _owner),
        ],
      );
      addTearDown(container.dispose);

      await container.read(auth.domainOptInsProvider.future);
      await container
          .read(auth.domainOptInsProvider.notifier)
          .setEnabled(DomainScope.health, true);
      final repo = await container.read(healthMetricRepositoryProvider.future);
      final now = DateTime.utc(2026, 8, 27, 12);
      await repo.upsertAll([
        _metric(
          id: 'hk:steps:old',
          kind: HealthMetricKind.stepsDaily,
          capturedAt: now.subtract(const Duration(days: 2)),
        ),
        _metric(
          id: 'hc:hrv:new',
          kind: HealthMetricKind.hrvDaily,
          capturedAt: now.subtract(const Duration(hours: 2)),
        ),
        _metric(
          id: 'garmin:stress:new',
          kind: HealthMetricKind.stressDaily,
          capturedAt: now.subtract(const Duration(hours: 1)),
        ),
        _metric(
          id: 'manual:weight:new',
          kind: HealthMetricKind.weight,
          capturedAt: now.subtract(const Duration(days: 3)),
        ),
      ]);

      final summary = await container.read(
        healthSourceDataSummaryProvider.future,
      );
      expect(
        summary.platformLatestAt?.toUtc(),
        now.subtract(const Duration(hours: 2)),
      );
      expect(
        summary.garminLatestAt?.toUtc(),
        now.subtract(const Duration(hours: 1)),
      );
      expect(
        summary.manualLatestAt?.toUtc(),
        now.subtract(const Duration(days: 3)),
      );
    },
  );
}
