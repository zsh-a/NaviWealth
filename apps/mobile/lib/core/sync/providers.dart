import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:talker_dio_logger/talker_dio_logger.dart';

import '../../data/db/providers.dart';
import '../auth/providers.dart';
import '../logging/providers.dart';
import 'dio_sync_api_client.dart';
import 'drift_sync_storage.dart';
import 'op_applier.dart';
import 'sync_api_client.dart';
import 'sync_engine.dart';
import 'sync_scheduler.dart';
import 'sync_status.dart';

/// Auth token source. Stub returns `null` until FIR-30 wires real auth in;
/// every sync call will then 401 and the engine surfaces `failed`. This
/// is the intended early-development behaviour: visible in the status
/// indicator instead of crashing.
final syncAuthTokenProvider = Provider<Future<String?> Function()>((ref) {
  return () async => null;
});

/// Shared Dio instance pointed at the configured backend. We don't reuse
/// the market-data Dio because that one is wired with rate-limiting +
/// retry interceptors specific to free-tier price feeds; sync has its own
/// retry semantics.
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

/// Default applier registry — empty until each feature ticket registers
/// its table handler. The SyncEngine works correctly with zero handlers:
/// pulled ops get the LWW comparison + cursor advance, just nothing
/// materialised. Useful for early integration testing.
final syncOpApplierProvider = Provider<OpApplier>((ref) {
  return TableRoutingApplier({});
});

final syncStatusBusProvider = Provider<SyncStatusBus>((ref) {
  final bus = SyncStatusBus();
  ref.onDispose(bus.close);
  return bus;
});

final syncEngineProvider = FutureProvider<SyncEngine?>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  final outbox = DriftOutboxStore(db);
  final cursors = DriftCursorStore(db);
  final api = ref.watch(syncApiClientProvider);
  final applier = ref.watch(syncOpApplierProvider);
  final session = ref.watch(authSessionProvider);
  if (session == null) {
    return null;
  }
  final bus = ref.watch(syncStatusBusProvider);
  return SyncEngine(
    api: api,
    outbox: outbox,
    cursors: cursors,
    applier: applier,
    deviceId: session.deviceId,
    statusBus: bus,
    logger: ref.read(loggerProvider),
  );
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

/// Eager bootstrap hook for foreground sync.
///
/// Read this once from app bootstrap. It keeps a listener alive so login /
/// logout transitions create or dispose the scheduler, and starts each
/// authenticated scheduler as soon as it resolves.
final syncSchedulerBootstrapProvider = Provider<void>((ref) {
  ref.listen<AsyncValue<SyncScheduler?>>(syncSchedulerProvider, (_, next) {
    next.whenData((scheduler) => scheduler?.start());
  }, fireImmediately: true);
});
