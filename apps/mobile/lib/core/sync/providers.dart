import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naviwealth/core/sync/hlc.dart';

import '../../core/persistence/providers.dart';
import '../auth/providers.dart';
import '../config/providers.dart';
import '../data_management/providers.dart';
import '../logging/http_diagnostics_interceptor.dart';
import '../logging/providers.dart';
import 'dio_sync_api_client.dart';
import 'drift_sync_storage.dart';
import 'row_applier.dart';
import 'sync_api_client.dart';
import 'sync_backfill.dart';
import 'sync_engine.dart';
import 'sync_scheduler.dart';
import 'sync_scope.dart';
import 'sync_stability.dart';
import 'sync_status.dart';

/// Pull visibility is persisted separately for each identity and domain set.
final syncScopeProvider = FutureProvider<SyncScope?>((ref) async {
  final session = ref.watch(authSessionProvider);
  if (session == null) return null;
  final optIns = await ref.watch(domainOptInsProvider.future);
  return SyncScope(ownerUserId: session.userId, domains: optIns.toWire());
});

/// Shared Dio instance pointed at the configured backend.
final syncDioProvider = Provider<Dio>((ref) {
  final config = ref.watch(appConfigProvider);
  final dio = Dio(
    BaseOptions(
      baseUrl: config.apiBaseUrl,
      connectTimeout: const Duration(seconds: 10),
      sendTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 30),
    ),
  );
  dio.interceptors.add(
    HttpDiagnosticsInterceptor(
      logger: ref.read(loggerProvider),
      service: 'sync',
    ),
  );
  return dio;
});

final syncApiClientProvider = Provider<SyncApiClient>((ref) {
  final dio = ref.watch(syncDioProvider);
  final token = ref.watch(authSessionProvider)?.accessToken;
  // A superseded engine must never send another user's freshly rotated token
  // with its old device id, dirty rows or cursor.
  return DioSyncApiClient(dio: dio, tokenProvider: () async => token);
});

/// Generic, schema-driven applier for pulled row-states. One class covers
/// every syncable table (`docs/sync/sync-v3.md`).
final syncRowApplierProvider = Provider<RowApplier?>((ref) {
  final db = ref.watch(appDatabaseProvider).value;
  if (db == null) return null;
  return RowApplier(db);
});

final syncStatusBusProvider = Provider<SyncStatusBus>((ref) {
  final bus = SyncStatusBus();
  ref.onDispose(bus.close);
  return bus;
});

/// Live stream of sync status events seeded with the bus's current snapshot,
/// so a status page opened mid-cycle paints immediately.
final syncStatusEventStreamProvider = StreamProvider<SyncStatusEvent>((ref) {
  final bus = ref.watch(syncStatusBusProvider);
  return Stream<SyncStatusEvent>.multi((controller) {
    controller.add(bus.current);
    final subscription = bus.stream.listen(
      controller.add,
      onError: controller.addError,
      onDone: controller.close,
    );
    controller.onCancel = subscription.cancel;
  });
});

/// Last persisted pull cursor (server `seq`). `0` before the first sync.
/// Diagnostic-only; invalidated after each cycle.
final syncCursorProvider = FutureProvider<int>((ref) async {
  ref.watch(syncStatusEventStreamProvider);
  final scope = await ref.watch(syncScopeProvider.future);
  if (scope == null) return 0;
  final db = await ref.watch(appDatabaseProvider.future);
  return DriftCursorStore(db, scope: scope).readSeq();
});

/// Latest local HLC used to stamp local writes. Exposed for diagnostics and
/// any future sync freshness surfaces.
final syncLocalHlcProvider = FutureProvider<Hlc?>((ref) async {
  ref.watch(syncStatusEventStreamProvider);
  final db = await ref.watch(appDatabaseProvider.future);
  return DriftLocalClockStore(db).read();
});

/// Current pending-row depth (local mutations not yet confirmed by the
/// server). Re-runs whenever a status event lands.
final syncOutboxDepthProvider = FutureProvider<int>((ref) async {
  ref.watch(syncStatusEventStreamProvider);
  final scope = await ref.watch(syncScopeProvider.future);
  if (scope == null) return 0;
  final db = await ref.watch(appDatabaseProvider.future);
  return DriftPendingRows(
    db,
    ownerUserId: scope.ownerUserId,
    domains: scope.domains,
  ).depth();
});

final syncStabilityReportProvider = FutureProvider<SyncStabilityReport>((
  ref,
) async {
  ref.watch(syncStatusEventStreamProvider);
  final session = ref.watch(authSessionProvider);
  if (session == null) return SyncStabilityReport(samples: const []);
  final db = await ref.watch(appDatabaseProvider.future);
  return DriftSyncStabilityStore(db, ownerUserId: session.userId).readReport();
});

final syncEngineProvider = FutureProvider<SyncEngine?>((ref) async {
  final session = ref.watch(authSessionProvider);
  if (session == null) return null;
  final api = ref.watch(syncApiClientProvider);
  final scope = await ref.watch(syncScopeProvider.future);
  if (scope == null || !ref.mounted) return null;
  final db = await ref.watch(appDatabaseProvider.future);
  final resetCursor = await RowApplier(db).prepareCompatibility();
  if (!ref.mounted) return null;
  if (resetCursor) {
    ref
        .read(loggerProvider)
        .i('sync: replay current rows for client schema change');
  }
  final outbox = DriftOutboxStore(db);
  final resetHandler = await ref.watch(
    dataManagementDomainResetHandlerProvider.future,
  );
  if (!ref.mounted) return null;
  final engine = SyncEngine(
    api: api,
    pending: DriftPendingRows(
      db,
      ownerUserId: session.userId,
      domains: scope.domains,
    ),
    cursors: DriftCursorStore(db, scope: scope),
    applier: RowApplier(db, ownerUserId: session.userId),
    deviceId: session.deviceId,
    statusBus: ref.watch(syncStatusBusProvider),
    generationStore: DriftDomainGenerationStore(
      db,
      ownerUserId: session.userId,
    ),
    resetHandler: resetHandler,
    logger: ref.read(loggerProvider),
    stabilityRecorder: DriftSyncStabilityStore(db, ownerUserId: session.userId),
    enabledDomains: scope.domains,
  );
  ref.onDispose(engine.stop);

  final backfilled = await SyncBackfill(
    db: db,
    outbox: outbox,
    session: session,
  ).enqueueMissingLocalRows();
  if (!ref.mounted) return null;
  if (backfilled > 0) {
    ref
        .read(loggerProvider)
        .i('sync: queued $backfilled historical local rows');
  }
  return engine;
});

final syncSchedulerProvider = FutureProvider<SyncScheduler?>((ref) async {
  final engine = await ref.watch(syncEngineProvider.future);
  if (engine == null) return null;
  final scheduler = SyncScheduler(
    engine: engine,
    logger: ref.read(loggerProvider),
  );
  ref.onDispose(scheduler.stop);
  return scheduler;
});

/// Eager bootstrap hook for foreground sync. Read once from app bootstrap.
final syncSchedulerBootstrapProvider = Provider<void>((ref) {
  ref.listen<AsyncValue<SyncScheduler?>>(syncSchedulerProvider, (_, next) {
    next.whenData((scheduler) => scheduler?.start());
  }, fireImmediately: true);
});
