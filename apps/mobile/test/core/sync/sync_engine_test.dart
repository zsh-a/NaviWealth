import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/auth/auth_session.dart';
import 'package:naviwealth/core/auth/providers.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/persistence/domain_enums.dart';
import 'package:naviwealth/core/persistence/providers.dart';
import 'package:naviwealth/core/sync/clock.dart';
import 'package:naviwealth/core/sync/domain_generation.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/errors.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/op_outbox.dart';
import 'package:naviwealth/core/sync/providers.dart';
import 'package:naviwealth/core/sync/row_applier.dart';
import 'package:naviwealth/core/sync/sync_api_client.dart';
import 'package:naviwealth/core/sync/sync_engine.dart';
import 'package:naviwealth/core/sync/sync_status.dart';

import '../../core/persistence/test_database.dart';
import '_fake_api.dart';

const _dev = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
const _otherDev = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';

/// In-memory [PendingRows] driven by enqueued ops + a row store.
///
/// Mirrors what `DriftPendingRows` does over Drift: pointers come from the
/// op queue (oldest first), and `readRow` snapshots the current row state.
class FakePendingRows implements PendingRows {
  final List<PendingPointer> _pointers = [];
  final Map<String, Map<String, Object?>> _rows = {};

  /// Queue a dirty pointer and set the row's current state.
  void put({
    required String opId,
    required String table,
    required String rowId,
    required Map<String, Object?> row,
  }) {
    _pointers.add(PendingPointer(opId: opId, table: table, rowId: rowId));
    _rows['$table $rowId'] = row;
  }

  /// Queue a dirty pointer whose row has already disappeared locally.
  void putStale({
    required String opId,
    required String table,
    required String rowId,
  }) {
    _pointers.add(PendingPointer(opId: opId, table: table, rowId: rowId));
  }

  @override
  Future<int> depth() async => _pointers.length;

  @override
  Future<List<PendingPointer>> pointers() async => List.unmodifiable(_pointers);

  @override
  Future<Map<String, Object?>?> readRow(String table, String rowId) async =>
      _rows['$table $rowId'];

  @override
  Future<void> clear(Iterable<String> opIds) async {
    final set = opIds.toSet();
    _pointers.removeWhere((p) => set.contains(p.opId));
  }
}

class RecordingDomainResetHandler implements DomainResetHandler {
  final List<String> domains = <String>[];

  @override
  Future<void> resetLocalDomain(String domain) async => domains.add(domain);
}

/// Recording [RowApplier]-shaped fake. RowApplier is a concrete class, so the
/// engine takes it directly — this captures applied rows for assertions.
class RecordingApplier extends RowApplier {
  RecordingApplier(super.db);

  final List<RowChange> applied = [];
  RowApplyReport? nextReport;

  @override
  Future<RowApplyReport> applyWithReport(List<RowChange> rows) async {
    applied.addAll(rows);
    final report = nextReport;
    nextReport = null;
    return report ??
        RowApplyReport(
          attempted: rows.length,
          written: rows.length,
          skippedLocalWins: 0,
          skippedUnknownDomain: 0,
          skippedUnsupportedTable: 0,
          skippedEmptyPayload: 0,
        );
  }
}

Map<String, Object?> _rowState({
  String id = 'A1',
  String name = 'Cash',
  required String hlc,
  bool deleted = false,
}) {
  return <String, Object?>{
    'id': id,
    'name': name,
    'hlc': hlc,
    'deleted_at': deleted ? 1_700_000_000 : null,
  };
}

String _hlc(int wall, {String node = _dev}) =>
    Hlc(wallMillis: wall, counter: 0, nodeId: node).toString();

void main() {
  late FakeSyncApiClient api;
  late FakePendingRows pending;
  late InMemoryCursorStore cursors;
  late RecordingApplier applier;
  late SyncStatusBus bus;
  late FixedClock clock;
  late SyncEngine engine;
  late AppDatabase db;

  setUp(() {
    db = makeTestDatabase();
    api = FakeSyncApiClient();
    pending = FakePendingRows();
    cursors = InMemoryCursorStore();
    applier = RecordingApplier(db);
    bus = SyncStatusBus();
    clock = FixedClock(2_000_000_000_000);
    engine = SyncEngine(
      api: api,
      pending: pending,
      cursors: cursors,
      applier: applier,
      deviceId: _dev,
      statusBus: bus,
      clock: clock,
    );
  });

  tearDown(() => db.close());

  group('SyncEngine cycle', () {
    test(
      'new server generation resets local domain before accepting rows',
      () async {
        final generations = InMemoryDomainGenerationStore();
        final resets = RecordingDomainResetHandler();
        api.domainGenerations['finance'] = 1;
        engine = SyncEngine(
          api: api,
          pending: pending,
          cursors: cursors,
          applier: applier,
          deviceId: _dev,
          statusBus: bus,
          clock: clock,
          generationStore: generations,
          resetHandler: resets,
        );

        final result = await engine.run();

        expect(result.success, isTrue);
        expect(resets.domains, contains('finance'));
        expect(generations.values['finance'], 1);
      },
    );

    test('happy path: pushes dirty rows and clears their pointers', () async {
      pending.put(
        opId: 'op-1',
        table: 'accounts',
        rowId: 'A1',
        row: _rowState(id: 'A1', hlc: _hlc(1_500_000_000_000)),
      );
      pending.put(
        opId: 'op-2',
        table: 'accounts',
        rowId: 'A2',
        row: _rowState(id: 'A2', hlc: _hlc(1_500_000_000_001)),
      );

      final result = await engine.run();

      expect(result.success, isTrue);
      expect(result.pushed, 2);
      expect(api.pushedBatches.single.map((c) => c.id), ['A1', 'A2']);
      // D-1.4: outbound rows carry the LifeOS domain prefix.
      expect(api.pushedBatches.single.map((c) => c.table).toSet(), <String>{
        'fin:accounts',
      });
      expect(await pending.depth(), 0, reason: 'pointers acknowledged');
    });

    test('multiple ops on the same row collapse to one RowChange', () async {
      pending.put(
        opId: 'op-1',
        table: 'accounts',
        rowId: 'A1',
        row: _rowState(id: 'A1', name: 'Old', hlc: _hlc(1_000)),
      );
      pending.put(
        opId: 'op-2',
        table: 'accounts',
        rowId: 'A1',
        row: _rowState(id: 'A1', name: 'New', hlc: _hlc(2_000)),
      );

      final result = await engine.run();

      expect(result.pushed, 1, reason: 'one row → one push');
      expect(api.pushedBatches.single.single.id, 'A1');
      // Both op pointers are acknowledged.
      expect(await pending.depth(), 0);
    });

    test('server-rejected push rows stay dirty', () async {
      pending.put(
        opId: 'op-1',
        table: 'knowledge_notes',
        rowId: 'K1',
        row: _rowState(id: 'K1', hlc: _hlc(1_500_000_000_000)),
      );
      api.programmedResponses.add(
        const SyncResponse(seq: 0, changes: [], more: false, accepted: []),
      );

      final result = await engine.run();

      expect(result.success, isTrue);
      expect(result.pushed, 0);
      expect(await pending.depth(), 1);
      expect(api.pushedBatches.single.single.table, 'know:knowledge_notes');
    });

    test('stale dirty pointers clear without pushing an empty row', () async {
      pending.putStale(opId: 'op-stale', table: 'accounts', rowId: 'A1');

      final result = await engine.run();

      expect(result.success, isTrue);
      expect(result.pushed, 0);
      expect(api.pushedBatches.single, isEmpty);
      expect(await pending.depth(), 0);
    });

    test('health metrics use the health row family', () async {
      pending.put(
        opId: 'op-1',
        table: 'health_metrics',
        rowId: 'H1',
        row: _rowState(id: 'H1', hlc: _hlc(1_500_000_000_000)),
      );

      await engine.run();

      expect(api.pushedBatches.single.single.table, 'health:health_metrics');
      expect(await pending.depth(), 0);
    });

    test('pull applies peer rows and advances the cursor by seq', () async {
      api.seedRemote(
        RowChange(
          table: 'accounts',
          id: 'R1',
          payload: _rowState(
            id: 'R1',
            hlc: _hlc(9, node: _otherDev),
          ),
          version: _hlc(9, node: _otherDev),
          deleted: false,
        ),
        deviceId: _otherDev,
      );

      final result = await engine.run();

      expect(result.success, isTrue);
      expect(result.pulled, 1);
      expect(applier.applied.single.id, 'R1');
      expect(await cursors.readSeq(), greaterThan(0));
    });

    test('reports remote rows skipped by local LWW', () async {
      api.seedRemote(
        RowChange(
          table: 'accounts',
          id: 'R1',
          payload: _rowState(
            id: 'R1',
            hlc: _hlc(9, node: _otherDev),
          ),
          version: _hlc(9, node: _otherDev),
          deleted: false,
        ),
        deviceId: _otherDev,
      );
      applier.nextReport = const RowApplyReport(
        attempted: 1,
        written: 0,
        skippedLocalWins: 1,
        skippedUnknownDomain: 0,
        skippedUnsupportedTable: 0,
        skippedEmptyPayload: 0,
      );

      final result = await engine.run();

      expect(result.success, isTrue);
      expect(result.pulled, 0);
      expect(result.conflicts.remoteRows, 1);
      expect(result.conflicts.localWins, 1);
      expect(bus.current.conflicts.localWins, 1);
    });

    test('pull filters out the caller-authored rows', () async {
      // A row authored by this device must not echo back.
      api.seedRemote(
        RowChange(
          table: 'accounts',
          id: 'MINE',
          payload: _rowState(id: 'MINE', hlc: _hlc(5)),
          version: _hlc(5),
          deleted: false,
        ),
        deviceId: _dev,
      );

      final result = await engine.run();

      expect(result.pulled, 0);
      expect(applier.applied, isEmpty);
    });

    test('empty cycle still succeeds and adopts the server seq', () async {
      // Seed a peer row so the server seq is non-zero, but the engine has
      // nothing dirty itself.
      api.seedRemote(
        RowChange(
          table: 'accounts',
          id: 'R1',
          payload: _rowState(
            id: 'R1',
            hlc: _hlc(1, node: _otherDev),
          ),
          version: _hlc(1, node: _otherDev),
          deleted: false,
        ),
        deviceId: _otherDev,
      );

      final result = await engine.run();

      expect(result.success, isTrue);
      expect(await cursors.readSeq(), 1);
    });

    test('concurrent run() calls share one in-flight cycle', () async {
      pending.put(
        opId: 'op-1',
        table: 'accounts',
        rowId: 'A1',
        row: _rowState(id: 'A1', hlc: _hlc(1_000)),
      );
      final f1 = engine.run();
      final f2 = engine.run();
      expect(identical(f1, f2), isTrue);
      await Future.wait([f1, f2]);
      expect(api.syncCalls.length, 1, reason: 'no duplicate request');
    });

    test('multi-page pull drains until more = false', () async {
      api.pageLimit = 100;
      for (var i = 0; i < 250; i++) {
        api.seedRemote(
          RowChange(
            table: 'accounts',
            id: 'R$i',
            payload: _rowState(
              id: 'R$i',
              hlc: _hlc(i + 1, node: _otherDev),
            ),
            version: _hlc(i + 1, node: _otherDev),
            deleted: false,
          ),
          deviceId: _otherDev,
        );
      }

      final result = await engine.run();

      expect(result.success, isTrue);
      expect(applier.applied.length, 250);
      expect(api.syncCalls.length, greaterThanOrEqualTo(3));
    });

    test('partial pull progress is reported when a later page fails', () async {
      final firstRemote = RowChange(
        table: 'fin:accounts',
        id: 'R1',
        payload: _rowState(
          id: 'R1',
          hlc: _hlc(9, node: _otherDev),
        ),
        version: _hlc(9, node: _otherDev),
        deleted: false,
        deviceId: _otherDev,
        seq: 1,
      );
      api.programmedResponses
        ..add(SyncResponse(seq: 1, changes: [firstRemote], more: true))
        ..add(SyncException(SyncErrorKind.network));

      final result = await engine.run();

      expect(result.success, isFalse);
      expect(result.pulled, 1);
      expect(result.conflicts.remoteRows, 1);
      expect(result.conflicts.appliedRows, 1);
      expect(applier.applied.single.id, 'R1');
      expect(await cursors.readSeq(), 1);
      expect(api.syncCalls, hasLength(2));
      expect(api.syncCalls[1].since, 1);
      expect(engine.state, EngineState.backoff);
      expect(bus.current.status, SyncStatus.offline);
      expect(bus.current.conflicts.remoteRows, 1);
    });
  });

  group('SyncEngine error handling', () {
    test('network failure → offline status + backoff scheduled', () async {
      api.programmedResponses.add(SyncException(SyncErrorKind.network));
      pending.put(
        opId: 'op-1',
        table: 'accounts',
        rowId: 'A1',
        row: _rowState(id: 'A1', hlc: _hlc(1_000)),
      );

      final result = await engine.run();

      expect(result.success, isFalse);
      expect(bus.current.status, SyncStatus.offline);
      expect(engine.state, EngineState.backoff);
      expect(engine.nextBackoff, isNotNull);
      // Pointer not cleared — retried next cycle.
      expect(await pending.depth(), 1);
    });

    test('protocol version mismatch → failed status, engine halts', () async {
      api.programmedResponses.add(
        SyncException(
          SyncErrorKind.protocolVersion,
          statusCode: 426,
          code: 'protocol_version',
        ),
      );

      final result = await engine.run();

      expect(result.success, isFalse);
      expect(bus.current.status, SyncStatus.failed);
      expect(engine.state, EngineState.halted);
    });

    test('429 Retry-After is honoured by the backoff delay', () async {
      api.programmedResponses.add(
        SyncException(
          SyncErrorKind.rateLimited,
          statusCode: 429,
          retryAfter: const Duration(seconds: 12),
        ),
      );

      final result = await engine.run();

      expect(result.success, isFalse);
      expect(engine.nextBackoff!.inSeconds, greaterThanOrEqualTo(12));
    });

    test('a successful cycle resets the backoff', () async {
      api.programmedResponses.add(SyncException(SyncErrorKind.network));
      await engine.run();
      expect(engine.nextBackoff, isNotNull);

      final result = await engine.run();
      expect(result.success, isTrue);
      expect(engine.nextBackoff, isNull);
      expect(bus.current.status, SyncStatus.online);
    });
  });

  group('SyncEngine.stampHlc', () {
    test('produces monotonically increasing HLCs', () async {
      final a = await engine.stampHlc(overrideNowMillis: 1_500_000_000_000);
      final b = await engine.stampHlc(overrideNowMillis: 1_500_000_000_000);
      final c = await engine.stampHlc(overrideNowMillis: 1_500_000_000_001);
      expect(a < b, isTrue);
      expect(b < c, isTrue);
      expect(a.nodeId, _dev);
    });
  });

  group('syncEngineProvider', () {
    test('rebuilds the engine when an auth session appears', () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final sessionState = StateProvider<AuthSession?>((_) => null);
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWith((_) async => db),
          authSessionProvider.overrideWith((ref) => ref.watch(sessionState)),
          syncApiClientProvider.overrideWithValue(FakeSyncApiClient()),
        ],
      );
      addTearDown(container.dispose);

      expect(await container.read(syncEngineProvider.future), isNull);

      container.read(sessionState.notifier).state = AuthSession(
        accessToken: 'token',
        expiresAt: DateTime.utc(2099),
        userId: 'user-1',
        deviceId: _dev,
      );
      await Future<void>.delayed(Duration.zero);

      final rebuilt = await container.read(syncEngineProvider.future);
      expect(rebuilt, isNotNull);
      expect(rebuilt!.deviceId, _dev);
    });

    test('resets a stale pull cursor on applier-version bump', () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final cursors = DriftCursorStore(db);
      // A leftover v1-era cursor.
      await cursors.writeSeq(1287);

      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWith((_) async => db),
          authSessionProvider.overrideWith(
            (_) => AuthSession(
              accessToken: 'token',
              expiresAt: DateTime.utc(2099),
              userId: 'user-1',
              deviceId: _dev,
            ),
          ),
          syncApiClientProvider.overrideWithValue(FakeSyncApiClient()),
        ],
      );
      addTearDown(container.dispose);

      expect(await container.read(syncEngineProvider.future), isNotNull);
      // The cursor row was wiped → readSeq falls back to 0.
      expect(await cursors.readSeq(), 0);

      final version = await db
          .customSelect(
            "SELECT value FROM sync_meta WHERE key = 'sync.applier_version'",
          )
          .getSingle();
      expect(version.read<String>('value'), '7');
    });

    test('backfills historical local rows into the outbox', () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      await db
          .into(db.accounts)
          .insert(
            AccountsCompanion.insert(
              id: 'cash-1',
              type: AccountCategory.cash,
              name: 'Cash Wallet',
              currency: 'CNY',
              category: const Value(AccountSide.asset),
              ownerUserId: 'user-1',
              updatedAt: DateTime.utc(2026, 1, 1),
              updatedByDevice: 'legacy-device',
              hlc: const Hlc(
                wallMillis: 1,
                counter: 0,
                nodeId: 'legacy-device',
              ),
            ),
          );

      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWith((_) async => db),
          authSessionProvider.overrideWith(
            (_) => AuthSession(
              accessToken: 'token',
              expiresAt: DateTime.utc(2099),
              userId: 'user-1',
              deviceId: _dev,
            ),
          ),
          syncApiClientProvider.overrideWithValue(FakeSyncApiClient()),
        ],
      );
      addTearDown(container.dispose);

      expect(await container.read(syncEngineProvider.future), isNotNull);

      final pending = DriftPendingRows(db);
      final pointers = await pending.pointers();
      expect(
        pointers.any((p) => p.table == 'accounts' && p.rowId == 'cash-1'),
        isTrue,
      );
    });
  });
}
