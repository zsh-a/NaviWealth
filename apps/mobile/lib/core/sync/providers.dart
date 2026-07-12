import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:talker_dio_logger/talker_dio_logger.dart';

import '../../core/persistence/app_database.dart';
import '../../core/persistence/providers.dart';
import '../auth/providers.dart';
import '../config/providers.dart';
import '../data_management/providers.dart';
import '../logging/providers.dart';
import 'dio_sync_api_client.dart';
import 'drift_sync_storage.dart';
import 'row_applier.dart';
import 'sync_api_client.dart';
import 'sync_backfill.dart';
import 'sync_engine.dart';
import 'sync_scheduler.dart';
import 'sync_status.dart';

/// Auth token source. Reads the current access token from
/// [authSessionProvider] on every call so a refresh / re-login is picked up
/// by the next request without rebuilding the API client.
final syncAuthTokenProvider = Provider<Future<String?> Function()>((ref) {
  return () async => ref.read(authSessionProvider)?.accessToken;
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
  dio.interceptors.add(TalkerDioLogger(talker: ref.read(talkerProvider)));
  return dio;
});

final syncApiClientProvider = Provider<SyncApiClient>((ref) {
  final dio = ref.watch(syncDioProvider);
  final tokenFn = ref.watch(syncAuthTokenProvider);
  return DioSyncApiClient(dio: dio, tokenProvider: tokenFn);
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
  final db = await ref.watch(appDatabaseProvider.future);
  return DriftCursorStore(db).readSeq();
});

/// Latest local HLC used to stamp local writes. Exposed for diagnostics and
/// any future sync freshness surfaces.
final syncLocalHlcProvider = FutureProvider<Hlc?>((ref) async {
  ref.watch(syncStatusEventStreamProvider);
  final db = await ref.watch(appDatabaseProvider.future);
  return DriftCursorStore(db).readLocalHlc();
});

/// Current pending-row depth (local mutations not yet confirmed by the
/// server). Re-runs whenever a status event lands.
final syncOutboxDepthProvider = FutureProvider<int>((ref) async {
  ref.watch(syncStatusEventStreamProvider);
  final db = await ref.watch(appDatabaseProvider.future);
  return DriftOutboxStore(db).depth();
});

final syncEngineProvider = FutureProvider<SyncEngine?>((ref) async {
  final session = ref.watch(authSessionProvider);
  if (session == null) return null;

  final db = await ref.watch(appDatabaseProvider.future);
  final resetCursor = await _ensureSyncApplierVersion(db);
  if (resetCursor) {
    ref.read(loggerProvider).i('sync: reset pull cursor for v3 row-state');
  }
  final outbox = DriftOutboxStore(db);
  final resetHandler = await ref.watch(
    dataManagementDomainResetHandlerProvider.future,
  );
  final engine = SyncEngine(
    api: ref.watch(syncApiClientProvider),
    pending: DriftPendingRows(db),
    cursors: DriftCursorStore(db),
    applier: RowApplier(db),
    deviceId: session.deviceId,
    statusBus: ref.watch(syncStatusBusProvider),
    generationStore: DriftDomainGenerationStore(
      db,
      ownerUserId: session.userId,
    ),
    resetHandler: resetHandler,
    logger: ref.read(loggerProvider),
  );

  final backfilled = await SyncBackfill(
    db: db,
    outbox: outbox,
    session: session,
  ).enqueueMissingLocalRows();
  if (backfilled > 0) {
    ref
        .read(loggerProvider)
        .i('sync: queued $backfilled historical local rows');
  }
  return engine;
});

/// Bumped whenever the row-state codec changes; a mismatch wipes the pull
/// cursor so the next sync re-pulls from `seq = 0`. v1 → v2 is one such bump
/// (the v1 cursor was an HLC string, not an integer `seq`).
const _kSyncApplierVersionKey = 'sync.applier_version';
const _kSyncApplierVersion = '7';

Future<bool> _ensureSyncApplierVersion(AppDatabase db) async {
  final row = await db
      .customSelect(
        'SELECT value FROM sync_meta WHERE key = ?',
        variables: [Variable.withString(_kSyncApplierVersionKey)],
      )
      .getSingleOrNull();
  final current = row?.read<String>('value');
  if (current == _kSyncApplierVersion) return false;
  await db.transaction(() async {
    await db.customStatement('DELETE FROM sync_meta WHERE key = ?', [
      'sync.cursor',
    ]);
    await db.customStatement(
      'INSERT INTO sync_meta(key, value) VALUES (?, ?) '
      'ON CONFLICT(key) DO UPDATE SET value = excluded.value',
      [_kSyncApplierVersionKey, _kSyncApplierVersion],
    );
  });
  return true;
}

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
