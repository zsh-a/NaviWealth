import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/features/health/data/health_metric_repository.dart';
import 'package:naviwealth/features/health/data/health_platform_adapter.dart';
import 'package:naviwealth/features/health/data/health_refresh_coordinator.dart';
import 'package:naviwealth/features/health/data/health_sync_service.dart';

import '../../../core/persistence/test_database.dart';

class _AvailablePlatform implements HealthPlatformAdapter {
  int fetchCalls = 0;

  @override
  Future<bool> hasPermissions() async => true;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<bool> requestPermissions() async => true;

  @override
  Future<HealthPlatformSnapshot> fetchRange({
    required DateTime from,
    required DateTime to,
  }) async {
    fetchCalls += 1;
    return const HealthPlatformSnapshot.empty();
  }
}

MutationStamper _stamper() => MutationStamper(
  currentUserId: () async => 'owner',
  deviceId: () async => 'device',
  stampHlc: () async => const Hlc(wallMillis: 1, counter: 0, nodeId: 'device'),
);

void main() {
  late AppDatabase db;
  late _AvailablePlatform platform;
  late HealthSyncService service;

  setUp(() {
    db = makeTestDatabase();
    platform = _AvailablePlatform();
    service = HealthSyncService(
      adapter: platform,
      repository: HealthMetricRepository(db: db, outbox: InMemoryOutboxStore()),
      stamper: _stamper(),
    );
  });

  tearDown(() => db.close());

  test('refresh combines platform and Garmin outcomes', () async {
    var garminCalls = 0;
    final coordinator = HealthRefreshCoordinator(
      platform: service,
      refreshGarmin: () async {
        garminCalls += 1;
        return const HealthRefreshSourceResult(
          source: HealthRefreshSource.garmin,
          outcome: HealthRefreshOutcome.synced,
          imported: 7,
        );
      },
    );

    final result = await coordinator.refreshConnectedSources();

    expect(platform.fetchCalls, 1);
    expect(garminCalls, 1);
    expect(result.syncedCount, 2);
    expect(result.failedCount, 0);
    expect(result.sources.last.imported, 7);
  });

  test('concurrent refresh gestures share one import', () async {
    final releaseGarmin = Completer<void>();
    var garminCalls = 0;
    final coordinator = HealthRefreshCoordinator(
      platform: service,
      refreshGarmin: () async {
        garminCalls += 1;
        await releaseGarmin.future;
        return const HealthRefreshSourceResult(
          source: HealthRefreshSource.garmin,
          outcome: HealthRefreshOutcome.synced,
        );
      },
    );

    final first = coordinator.refreshConnectedSources();
    final second = coordinator.refreshConnectedSources();
    expect(identical(first, second), isTrue);

    releaseGarmin.complete();
    await Future.wait(<Future<HealthRefreshResult>>[first, second]);
    expect(platform.fetchCalls, 1);
    expect(garminCalls, 1);
  });
}
