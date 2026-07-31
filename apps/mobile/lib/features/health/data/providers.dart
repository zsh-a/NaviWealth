/// HealthOS Riverpod wiring (`docs/domains/healthos-domain.md` §3, D-2.1 +
/// D-2.2).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/persistence/providers.dart';
import '../../../core/sync/mutation_context.dart';
import '../../../core/sync/outbox_provider.dart';
import '../../../design_system/preferences/theme_preferences.dart';
import 'garmin/garmin_snapshot_writer.dart';
import 'garmin/garmin_sync_controller.dart';
import 'health_metric_repository.dart';
import 'health_metric_write_service.dart';
import 'health_platform_adapter.dart';
import 'health_platform_adapter_factory.dart';
import 'health_refresh_coordinator.dart';
import 'health_sync_service.dart';
import 'health_sync_status.dart';

export 'garmin/garmin_region_preference.dart'
    show GarminRegion, GarminRegionX, garminRegionProvider;
// garminSyncControllerProvider is re-exported from garmin_sync_controller.dart.
export 'garmin/garmin_sync_controller.dart'
    show
        GarminSyncController,
        GarminSyncState,
        GarminInitial,
        GarminRestoring,
        GarminPendingMfa,
        GarminConnected,
        GarminSyncing,
        GarminError,
        garminSyncControllerProvider;
export 'health_refresh_coordinator.dart'
    show
        HealthRefreshCoordinator,
        HealthRefreshOutcome,
        HealthRefreshResult,
        HealthRefreshSource,
        HealthRefreshSourceResult;

/// Async repository — awaits the database + cross-domain outbox so a
/// shell-only build doesn't crash if Health is opt-in OFF.
final healthMetricRepositoryProvider = FutureProvider<HealthMetricRepository>((
  ref,
) async {
  final db = await ref.watch(appDatabaseProvider.future);
  final outbox = await ref.watch(outboxStoreProvider.future);
  return HealthMetricRepository(db: db, outbox: outbox);
});

/// Platform adapter. Native targets get the real HealthKit /
/// Health Connect impl; web / desktop get a not-supported stub.
/// Tests override this with a [FakeHealthPlatformAdapter] or similar.
final healthPlatformAdapterProvider = Provider<HealthPlatformAdapter>(
  (ref) => createHealthPlatformAdapter(),
);

/// Orchestrator that ties adapter + repository + sync stamper. UI
/// callers (Settings "Sync now" button, future agent) await this
/// provider before invoking `syncRange` / `requestPermissions`.
final healthSyncServiceProvider = FutureProvider<HealthSyncService>((
  ref,
) async {
  final adapter = ref.watch(healthPlatformAdapterProvider);
  final repo = await ref.watch(healthMetricRepositoryProvider.future);
  final stamper = await ref.watch(mutationStamperProvider.future);
  return HealthSyncService(
    adapter: adapter,
    repository: repo,
    stamper: stamper,
    statusStore: HealthSyncStatusStore(ref.watch(sharedPreferencesProvider)),
  );
});

final healthSyncStatusProvider = Provider<HealthSyncStatus?>(
  (ref) => HealthSyncStatusStore(ref.watch(sharedPreferencesProvider)).read(),
);

final healthRefreshCoordinatorProvider =
    FutureProvider<HealthRefreshCoordinator>((ref) async {
      final platform = await ref.watch(healthSyncServiceProvider.future);
      return HealthRefreshCoordinator(
        platform: platform,
        refreshGarmin: () async {
          final before = ref.read(garminSyncControllerProvider);
          if (before is GarminRestoring || before is GarminSyncing) {
            return const HealthRefreshSourceResult(
              source: HealthRefreshSource.garmin,
              outcome: HealthRefreshOutcome.skipped,
            );
          }
          if (before case GarminError(
            :final issue,
          ) when issue.requiresReconnect) {
            return HealthRefreshSourceResult(
              source: HealthRefreshSource.garmin,
              outcome: HealthRefreshOutcome.failed,
              errorCode: issue.code,
            );
          }
          if (before is GarminPendingMfa) {
            return const HealthRefreshSourceResult(
              source: HealthRefreshSource.garmin,
              outcome: HealthRefreshOutcome.failed,
              errorCode: 'mfa_required',
            );
          }

          await ref.read(garminSyncControllerProvider.notifier).syncNow();
          return switch (ref.read(garminSyncControllerProvider)) {
            GarminConnected(:final totalMetrics) => HealthRefreshSourceResult(
              source: HealthRefreshSource.garmin,
              outcome: HealthRefreshOutcome.synced,
              imported: totalMetrics,
            ),
            GarminError(:final issue) => HealthRefreshSourceResult(
              source: HealthRefreshSource.garmin,
              outcome: HealthRefreshOutcome.failed,
              errorCode: issue.code,
            ),
            GarminPendingMfa() => const HealthRefreshSourceResult(
              source: HealthRefreshSource.garmin,
              outcome: HealthRefreshOutcome.failed,
              errorCode: 'mfa_required',
            ),
            _ => const HealthRefreshSourceResult(
              source: HealthRefreshSource.garmin,
              outcome: HealthRefreshOutcome.skipped,
            ),
          };
        },
      );
    });

final healthMetricWriteServiceProvider =
    FutureProvider<HealthMetricWriteService>((ref) async {
      final repo = await ref.watch(healthMetricRepositoryProvider.future);
      final stamper = await ref.watch(mutationStamperProvider.future);
      return HealthMetricWriteService(repository: repo, stamper: stamper);
    });

// ---------------------------------------------------------------------------
// Garmin providers
// ---------------------------------------------------------------------------

/// Garmin snapshot writer — writes Rust snapshots into Drift.
final garminSnapshotWriterProvider = FutureProvider<GarminSnapshotWriter>((
  ref,
) async {
  final repo = await ref.watch(healthMetricRepositoryProvider.future);
  final stamper = await ref.watch(mutationStamperProvider.future);
  return GarminSnapshotWriter(repository: repo, stamper: stamper);
});
