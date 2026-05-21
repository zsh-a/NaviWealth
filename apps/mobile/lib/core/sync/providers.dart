import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:talker_dio_logger/talker_dio_logger.dart';

import '../../data/db/app_database.dart';
import '../../data/db/providers.dart';
import '../../data/domain/hlc.dart';
import '../../data/repositories/account_op_applier.dart';
import '../../data/repositories/generic_op_applier.dart';
import '../auth/providers.dart';
import '../logging/providers.dart';
import 'dio_sync_api_client.dart';
import 'drift_sync_storage.dart';
import 'op_applier.dart';
import 'sync_api_client.dart';
import 'sync_backfill.dart';
import 'sync_engine.dart';
import 'sync_scheduler.dart';
import 'sync_status.dart';

/// Auth token source. Reads the current access token from
/// [authSessionProvider] on every call so a refresh / re-login is
/// picked up by the next request without rebuilding the API client.
final syncAuthTokenProvider = Provider<Future<String?> Function()>((ref) {
  return () async => ref.read(authSessionProvider)?.accessToken;
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

/// Default applier registry for tables that have local materialisers.
///
/// `accounts` keeps its hand-written typed applier (stricter validation,
/// pre-existing). Every other syncable table runs through
/// [GenericLwwApplier] which derives its column shape from Drift's
/// runtime metadata — adding a new synced table is just a wire-name
/// entry below.
final syncOpApplierProvider = Provider<OpApplier>((ref) {
  final db = ref.watch(appDatabaseProvider).value;
  if (db == null) return const NoopOpApplier();
  const genericTables = <String>[
    'assets',
    'journal_entries',
    'postings',
    'prices',
    'watchlist_items',
    'recurring_transactions',
    'liabilities',
    'amortization_entries',
    'fx_rates',
    'tags',
    'tag_links',
    'categories',
    'goals',
    'devices',
    'users',
    // Options Income Planner P0.
    'approved_underlyings',
    // Options Income Planner P3 — trade journal.
    'options_trade_journal',
  ];
  final handlers = <String, OpApplier>{
    'accounts': AccountOpApplier(db),
    for (final t in genericTables) t: GenericLwwApplier(db: db, tableName: t),
    // `settings` and `options_strategy_profile` are per-user singletons
    // keyed by `user_id` rather than the default `id` PK.
    'settings': GenericLwwApplier(
      db: db,
      tableName: 'settings',
      pkColumn: 'user_id',
    ),
    'options_strategy_profile': GenericLwwApplier(
      db: db,
      tableName: 'options_strategy_profile',
      pkColumn: 'user_id',
    ),
  };
  return TableRoutingApplier(handlers);
});

final syncStatusBusProvider = Provider<SyncStatusBus>((ref) {
  final bus = SyncStatusBus();
  ref.onDispose(bus.close);
  return bus;
});

/// Live stream of sync status events seeded with the bus's current
/// snapshot, so a status page opened mid-cycle paints immediately
/// instead of waiting for the next event.
final syncStatusEventStreamProvider = StreamProvider<SyncStatusEvent>((
  ref,
) async* {
  final bus = ref.watch(syncStatusBusProvider);
  yield bus.current;
  yield* bus.stream;
});

/// Last persisted pull cursor (HLC). Returns null before the first pull.
/// Diagnostic-only; consumers should invalidate after a sync to refresh.
final syncCursorProvider = FutureProvider<Hlc?>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  return DriftCursorStore(db).readCursor();
});

/// Latest local HLC used to stamp ops on this device. The freshness gate
/// (`docs/ai-architecture.md` §4.2) compares this against the cloud
/// read-model's `source_hlc_watermark` —— device ahead = read model stale.
final syncLocalHlcProvider = FutureProvider<Hlc?>((ref) async {
  ref.watch(syncStatusEventStreamProvider);
  final db = await ref.watch(appDatabaseProvider.future);
  return DriftCursorStore(db).readLocalHlc();
});

/// Current outbox depth (pending local ops not yet pushed). Re-runs every
/// time a status event lands so the count stays in step with the engine.
final syncOutboxDepthProvider = FutureProvider<int>((ref) async {
  ref.watch(syncStatusEventStreamProvider);
  final db = await ref.watch(appDatabaseProvider.future);
  return DriftOutboxStore(db).depth();
});

/// Per-table row counts from the local materialised tables, keyed by a
/// short identifier (e.g. `accounts_user`). Diagnostic-only — surfaced on
/// the Sync Status page so a "pulled N ops but UI shows nothing" mismatch
/// is immediately visible. Re-runs whenever a status event lands.
typedef LocalTableCounts = Map<String, int>;

/// Wire identifiers for the diagnostic counters, in display order. The UI
/// resolves each id to a localised label.
const List<String> kSyncLocalCountIds = [
  'accounts_user',
  'accounts_system',
  'journal_entries',
  'postings',
  'assets',
  'prices',
  'watchlist_items',
  'recurring_transactions',
  'liabilities',
  'tags',
];

const String _kLocalCountsSql = '''
  SELECT 'accounts_user'   AS t, COUNT(*) AS c FROM accounts          WHERE id NOT LIKE 'system-account:%' AND deleted_at IS NULL
  UNION ALL SELECT 'accounts_system',  COUNT(*) FROM accounts         WHERE id LIKE 'system-account:%' AND deleted_at IS NULL
  UNION ALL SELECT 'journal_entries',  COUNT(*) FROM journal_entries  WHERE deleted_at IS NULL
  UNION ALL SELECT 'postings',         COUNT(*) FROM postings         WHERE deleted_at IS NULL
  UNION ALL SELECT 'assets',           COUNT(*) FROM assets           WHERE deleted_at IS NULL
  UNION ALL SELECT 'prices',           COUNT(*) FROM prices           WHERE deleted_at IS NULL
  UNION ALL SELECT 'watchlist_items',  COUNT(*) FROM watchlist_items  WHERE deleted_at IS NULL
  UNION ALL SELECT 'recurring_transactions', COUNT(*) FROM recurring_transactions WHERE deleted_at IS NULL
  UNION ALL SELECT 'liabilities',      COUNT(*) FROM liabilities      WHERE deleted_at IS NULL
  UNION ALL SELECT 'tags',             COUNT(*) FROM tags             WHERE deleted_at IS NULL
''';

final syncLocalTableCountsProvider = FutureProvider<LocalTableCounts>((
  ref,
) async {
  ref.watch(syncStatusEventStreamProvider);
  final db = await ref.watch(appDatabaseProvider.future);
  final rows = await db.customSelect(_kLocalCountsSql).get();
  return {for (final r in rows) r.read<String>('t'): r.read<int>('c')};
});

final syncEngineProvider = FutureProvider<SyncEngine?>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  final resetCursor = await _ensureSyncApplierVersion(db);
  if (resetCursor) {
    ref.read(loggerProvider).i('sync: reset pull cursor for accounts applier');
  }
  final outbox = DriftOutboxStore(db);
  final cursors = DriftCursorStore(db);
  final api = ref.watch(syncApiClientProvider);
  final applier = ref.watch(syncOpApplierProvider);
  final session = ref.watch(authSessionProvider);
  if (session == null) {
    return null;
  }
  final bus = ref.watch(syncStatusBusProvider);
  final engine = SyncEngine(
    api: api,
    outbox: outbox,
    cursors: cursors,
    applier: applier,
    deviceId: session.deviceId,
    statusBus: bus,
    logger: ref.read(loggerProvider),
  );
  final backfilled = await SyncBackfill(
    db: db,
    outbox: outbox,
    engine: engine,
    session: session,
  ).enqueueMissingLocalRows();
  if (backfilled > 0) {
    ref
        .read(loggerProvider)
        .i('sync: queued $backfilled historical local rows');
  }
  return engine;
});

const _kSyncApplierVersionKey = 'sync.applier_version';
const _kSyncApplierVersion = '4';

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
