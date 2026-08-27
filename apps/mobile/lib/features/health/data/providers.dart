/// HealthOS Riverpod wiring (`docs/domains/healthos-domain.md` §3, D-2.1 +
/// D-2.2).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/domain_scope.dart';
import '../../../core/auth/providers.dart' as core_auth;
import '../../../core/persistence/providers.dart';
import '../../../core/sync/mutation_context.dart';
import '../../../core/sync/outbox_provider.dart';
import '../../../design_system/preferences/theme_preferences.dart';
import '../domain/health_metric_kind.dart';
import 'garmin/garmin_snapshot_writer.dart';
import 'garmin/garmin_sync_controller.dart';
import 'health_metric_repository.dart';
import 'health_metric_source.dart';
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

/// A lightweight, UI-neutral snapshot of the platform connection state.
///
/// Health Connect intentionally cannot report read permission state on
/// Android. The adapter normalizes that platform limitation, so consumers can
/// use this state for discovery without blocking a real sync attempt.
class HealthPlatformStatus {
  const HealthPlatformStatus({
    required this.available,
    required this.permissionsGranted,
    this.checkFailed = false,
  });

  const HealthPlatformStatus.unavailable()
    : available = false,
      permissionsGranted = false,
      checkFailed = false;

  const HealthPlatformStatus.failed()
    : available = false,
      permissionsGranted = false,
      checkFailed = true;

  final bool available;
  final bool permissionsGranted;
  final bool checkFailed;

  bool get needsPermission => available && !permissionsGranted;
  bool get ready => available && permissionsGranted;
}

/// Current native HealthKit / Health Connect availability and permission
/// state. It is deliberately kept separate from the last sync result: a
/// source can be connected while its most recent import still failed.
final healthPlatformStatusProvider =
    FutureProvider.autoDispose<HealthPlatformStatus>((ref) async {
      final adapter = ref.watch(healthPlatformAdapterProvider);
      try {
        final available = await adapter.isAvailable();
        if (!available) return const HealthPlatformStatus.unavailable();
        return HealthPlatformStatus(
          available: true,
          permissionsGranted: await adapter.hasPermissions(),
        );
      } on Object {
        return const HealthPlatformStatus.failed();
      }
    });

/// Latest local data grouped by source. The source identity is already
/// canonicalized at the metric boundary (`hk:`, `hc:`, `garmin:`, `manual:`),
/// so this provider only needs a small recent slice from each metric kind.
class HealthSourceDataSummary {
  const HealthSourceDataSummary({
    this.platformLatestAt,
    this.garminLatestAt,
    this.manualLatestAt,
  });

  final DateTime? platformLatestAt;
  final DateTime? garminLatestAt;
  final DateTime? manualLatestAt;
}

final Set<HealthMetricKind> _kHealthSourceSummaryKinds =
    HealthMetricKind.values.toSet()..remove(HealthMetricKind.unknown);

final healthSourceDataSummaryProvider =
    FutureProvider.autoDispose<HealthSourceDataSummary>((ref) async {
      final optIns = ref.watch(core_auth.domainOptInsProvider).value;
      if (optIns == null || !optIns.contains(DomainScope.health)) {
        return const HealthSourceDataSummary();
      }

      final repo = await ref.watch(healthMetricRepositoryProvider.future);
      final userId = await ref.read(currentUserIdProvider)();
      final byKind = await repo.listByKinds(
        ownerUserId: userId,
        kinds: _kHealthSourceSummaryKinds,
        // Only the newest rows matter for freshness. Keeping this bounded
        // avoids turning an operational status row into a history query.
        limit: 3,
      );

      DateTime? platformLatestAt;
      DateTime? garminLatestAt;
      DateTime? manualLatestAt;
      for (final metric in byKind.values.expand((rows) => rows)) {
        final source = sourceForHealthMetric(metric);
        switch (source) {
          case HealthMetricSource.garmin:
            garminLatestAt = _latestDate(garminLatestAt, metric.capturedAt);
          case HealthMetricSource.healthKit:
          case HealthMetricSource.healthConnect:
            platformLatestAt = _latestDate(platformLatestAt, metric.capturedAt);
          case HealthMetricSource.manual:
            manualLatestAt = _latestDate(manualLatestAt, metric.capturedAt);
          case HealthMetricSource.unknown:
            break;
        }
      }
      return HealthSourceDataSummary(
        platformLatestAt: platformLatestAt,
        garminLatestAt: garminLatestAt,
        manualLatestAt: manualLatestAt,
      );
    });

DateTime? _latestDate(DateTime? current, DateTime candidate) {
  if (current == null || candidate.isAfter(current)) return candidate;
  return current;
}

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
          if (before case GarminError(:final issue)
              when issue.requiresReconnect) {
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
