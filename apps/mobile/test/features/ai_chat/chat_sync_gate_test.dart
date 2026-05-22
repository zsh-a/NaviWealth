import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/clock.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/errors.dart';
import 'package:naviwealth/core/sync/op_outbox.dart';
import 'package:naviwealth/core/sync/row_applier.dart';
import 'package:naviwealth/core/sync/sync_api_client.dart';
import 'package:naviwealth/core/sync/sync_engine.dart';
import 'package:naviwealth/core/sync/sync_status.dart';
import 'package:naviwealth/data/db/app_database.dart';
import 'package:naviwealth/data/domain/hlc.dart';
import 'package:naviwealth/features/ai_chat/state/chat_sync_gate.dart';

import '../../core/sync/_fake_api.dart';
import '../../data/db/test_database.dart';

const _dev = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

/// In-memory [PendingRows] for the gate tests: a list of dirty pointers plus
/// their current row snapshots.
class _FakePendingRows implements PendingRows {
  final List<PendingPointer> _pointers = [];
  final Map<String, Map<String, Object?>> _rows = {};

  void put(String opId, String rowId) {
    _pointers.add(
      PendingPointer(opId: opId, table: 'accounts', rowId: rowId),
    );
    _rows['accounts $rowId'] = {
      'id': rowId,
      'name': 'x',
      'hlc': const Hlc(wallMillis: 1, counter: 0, nodeId: _dev).toString(),
      'deleted_at': null,
    };
  }

  @override
  Future<int> depth() async => _pointers.length;

  @override
  Future<List<PendingPointer>> pointers() async =>
      List.unmodifiable(_pointers);

  @override
  Future<Map<String, Object?>?> readRow(String table, String rowId) async =>
      _rows['$table $rowId'];

  @override
  Future<void> clear(Iterable<String> opIds) async {
    final set = opIds.toSet();
    _pointers.removeWhere((p) => set.contains(p.opId));
  }
}

({SyncEngine engine, FakeSyncApiClient api, _FakePendingRows pending})
_buildEngine(AppDatabase db, {Clock? clock}) {
  final api = FakeSyncApiClient();
  final pending = _FakePendingRows();
  final engine = SyncEngine(
    api: api,
    pending: pending,
    cursors: InMemoryCursorStore(),
    applier: RowApplier(db),
    deviceId: _dev,
    statusBus: SyncStatusBus(),
    clock: clock ?? FixedClock(2_000_000_000_000),
  );
  return (engine: engine, api: api, pending: pending);
}

/// [SyncApiClient] whose `sync()` completes only when the test signals it.
class _StallingApiClient implements SyncApiClient {
  _StallingApiClient(this._gate);
  final Completer<void> _gate;

  @override
  Future<SyncResponse> sync({
    required String deviceId,
    required int since,
    required List<RowChange> changes,
  }) async {
    await _gate.future;
    return const SyncResponse(seq: 0, changes: [], more: false);
  }
}

void main() {
  late AppDatabase db;

  setUp(() => db = makeTestDatabase());
  tearDown(() => db.close());

  group('ChatSyncGate.awaitFlush', () {
    test('returns clean when the outbox is empty (no sync invoked)', () async {
      final fixture = _buildEngine(db);
      final gate = ChatSyncGate(engine: fixture.engine);

      final outcome = await gate.awaitFlush();

      expect(outcome, ChatGateOutcome.clean);
      expect(
        fixture.api.syncCalls,
        isEmpty,
        reason: 'no pending rows → no sync attempt',
      );
    });

    test('drains pending rows then returns synced', () async {
      final fixture = _buildEngine(db);
      fixture.pending.put('1', 'A1');
      fixture.pending.put('2', 'A2');

      final gate = ChatSyncGate(engine: fixture.engine);
      final outcome = await gate.awaitFlush();

      expect(outcome, ChatGateOutcome.synced);
      expect(await fixture.pending.depth(), 0);
      expect(fixture.api.syncCalls, isNotEmpty);
    });

    test('returns degraded when sync errors', () async {
      final fixture = _buildEngine(db);
      fixture.api.programmedResponses.add(
        SyncException(SyncErrorKind.network),
      );
      fixture.pending.put('1', 'A1');

      final gate = ChatSyncGate(engine: fixture.engine);
      final outcome = await gate.awaitFlush();

      expect(outcome, ChatGateOutcome.degraded);
      // Rows stay pending so a later periodic sync retries them.
      expect(await fixture.pending.depth(), 1);
    });

    test('returns degraded when the sync exceeds the timeout', () async {
      final pending = _FakePendingRows()..put('1', 'A1');
      final blocker = Completer<void>();
      final engine = SyncEngine(
        api: _StallingApiClient(blocker),
        pending: pending,
        cursors: InMemoryCursorStore(),
        applier: RowApplier(db),
        deviceId: _dev,
        statusBus: SyncStatusBus(),
        clock: const SystemClock(),
      );

      final gate = ChatSyncGate(
        engine: engine,
        timeout: const Duration(milliseconds: 50),
      );
      final stopwatch = Stopwatch()..start();
      final outcome = await gate.awaitFlush();
      stopwatch.stop();

      expect(outcome, ChatGateOutcome.degraded);
      expect(stopwatch.elapsed.inMilliseconds, greaterThanOrEqualTo(45));
      expect(
        stopwatch.elapsed.inMilliseconds,
        lessThan(2000),
        reason: 'gate must release the chat input close to the timeout',
      );

      // Release the stalled sync so the engine can clean up.
      blocker.complete();
    });
  });
}
