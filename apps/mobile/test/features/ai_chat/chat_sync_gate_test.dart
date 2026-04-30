import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/clock.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/errors.dart';
import 'package:naviwealth/core/sync/op.dart';
import 'package:naviwealth/core/sync/op_applier.dart';
import 'package:naviwealth/core/sync/sync_api_client.dart';
import 'package:naviwealth/core/sync/sync_engine.dart';
import 'package:naviwealth/core/sync/sync_status.dart';
import 'package:naviwealth/data/domain/hlc.dart';
import 'package:naviwealth/features/ai_chat/state/chat_sync_gate.dart';

import '../../core/sync/_fake_api.dart';

class _NoopApplier implements OpApplier {
  @override
  Future<void> applyAll(List<Op> ops) async {}
}

const _dev = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

Op _localOp(String id, int wall) => Op(
      opId: id,
      tableName: 'accounts',
      rowId: 'row-$id',
      opType: OpType.update,
      fieldsDiff: const {'name': 'x'},
      hlc: Hlc(wallMillis: wall, counter: 0, nodeId: _dev),
      deviceId: _dev,
    );

({SyncEngine engine, FakeSyncApiClient api, InMemoryOutboxStore outbox})
    _buildEngine({Clock? clock, int? batchMaxOps}) {
  final api = FakeSyncApiClient();
  final outbox = InMemoryOutboxStore();
  final cursors = InMemoryCursorStore();
  final bus = SyncStatusBus();
  final engine = SyncEngine(
    api: api,
    outbox: outbox,
    cursors: cursors,
    applier: _NoopApplier(),
    deviceId: _dev,
    statusBus: bus,
    clock: clock ?? FixedClock(2_000_000_000_000),
    batchMaxOps: batchMaxOps ?? 500,
  );
  return (engine: engine, api: api, outbox: outbox);
}

/// SyncApiClient whose push completes only when the test signals it.
/// Pull is left as a no-op happy server reply so the engine doesn't
/// abort during the pull phase.
class _StallingApiClient implements SyncApiClient {
  _StallingApiClient(this._gate);
  final Completer<void> _gate;
  Hlc serverHlc = const Hlc(
    wallMillis: 1_000_000_000_000,
    counter: 0,
    nodeId: Hlc.serverNodeId,
  );

  @override
  Future<MeResponse> me() async => MeResponse(
        userId: 'u',
        serverNow: DateTime.now(),
        serverHlc: serverHlc,
      );

  @override
  Future<PushResponse> push({
    required String deviceId,
    required List<Op> ops,
  }) async {
    await _gate.future;
    return PushResponse(
      accepted: ops.length,
      rejected: const [],
      serverHlcHigh: serverHlc,
      serverNow: DateTime.now(),
    );
  }

  @override
  Future<PullResponse> pull({
    required String deviceId,
    required Hlc since,
    int limit = kPullPageMaxOps,
  }) async =>
      PullResponse(
        ops: const [],
        serverHlcHigh: serverHlc,
        hasMore: false,
        serverNow: DateTime.now(),
      );
}

void main() {
  group('ChatSyncGate.awaitFlush', () {
    test('returns clean when outbox is empty (no engine.run() invoked)',
        () async {
      final fixture = _buildEngine();
      final gate = ChatSyncGate(engine: fixture.engine);

      final outcome = await gate.awaitFlush();

      expect(outcome, ChatGateOutcome.clean);
      expect(fixture.api.pushedBatches, isEmpty,
          reason: 'no pending ops -> no push attempt');
    });

    test('drains pending ops then returns synced', () async {
      final fixture = _buildEngine();
      await fixture.outbox.enqueue(_localOp('1', 1_500_000_000_000));
      await fixture.outbox.enqueue(_localOp('2', 1_500_000_000_001));

      final gate = ChatSyncGate(engine: fixture.engine);
      final outcome = await gate.awaitFlush();

      expect(outcome, ChatGateOutcome.synced);
      expect(await fixture.outbox.depth(), 0);
      expect(fixture.api.pushedBatches.single.map((o) => o.opId),
          ['1', '2']);
    });

    test('returns degraded when push errors', () async {
      final fixture = _buildEngine();
      fixture.api.programmedResponses
          .add(SyncException(SyncErrorKind.network));
      await fixture.outbox.enqueue(_localOp('1', 1_500_000_000_000));

      final gate = ChatSyncGate(engine: fixture.engine);
      final outcome = await gate.awaitFlush();

      expect(outcome, ChatGateOutcome.degraded);
      // Ops stay in the outbox so a later periodic sync retries them.
      expect(await fixture.outbox.depth(), 1);
    });

    test('returns degraded when engine.run() exceeds the timeout', () async {
      final outbox = InMemoryOutboxStore();
      final blocker = Completer<void>();
      final api = _StallingApiClient(blocker);
      final engine = SyncEngine(
        api: api,
        outbox: outbox,
        cursors: InMemoryCursorStore(),
        applier: _NoopApplier(),
        deviceId: _dev,
        statusBus: SyncStatusBus(),
        clock: const SystemClock(),
      );
      await outbox.enqueue(_localOp('1', 1_500_000_000_000));

      final gate = ChatSyncGate(
        engine: engine,
        timeout: const Duration(milliseconds: 50),
      );
      final stopwatch = Stopwatch()..start();
      final outcome = await gate.awaitFlush();
      stopwatch.stop();

      expect(outcome, ChatGateOutcome.degraded);
      expect(stopwatch.elapsed.inMilliseconds, greaterThanOrEqualTo(45));
      expect(stopwatch.elapsed.inMilliseconds, lessThan(2000),
          reason: 'gate must release the chat input close to timeout, '
              'not stay stuck on the upstream push');

      // Release the stalled push so the engine can clean up before the
      // test ends.
      blocker.complete();
    });

    test('returns degraded when later batches fail (residual ops)',
        () async {
      final fixture = _buildEngine(batchMaxOps: 1);
      // First push succeeds; second push fails.
      fixture.api.programmedResponses.add(
        PushResponse(
          accepted: 1,
          rejected: const [],
          serverHlcHigh: fixture.api.serverHlc,
          serverNow: DateTime.now(),
        ),
      );
      fixture.api.programmedResponses
          .add(SyncException(SyncErrorKind.network));

      await fixture.outbox.enqueue(_localOp('a', 1_500_000_000_000));
      await fixture.outbox.enqueue(_localOp('b', 1_500_000_000_001));

      final gate = ChatSyncGate(engine: fixture.engine);
      final outcome = await gate.awaitFlush();

      expect(outcome, ChatGateOutcome.degraded);
      // First op acknowledged; second remains in outbox.
      expect(await fixture.outbox.depth(), 1);
    });
  });
}
