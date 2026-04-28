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

import '_fake_api.dart';

class _RecordingApplier implements OpApplier {
  final List<Op> applied = [];
  @override
  Future<void> applyAll(List<Op> ops) async {
    applied.addAll(ops);
  }
}

Op _localOp({
  required String id,
  required int wall,
  required String dev,
  String table = 'accounts',
  OpType type = OpType.update,
  Map<String, Object?>? diff = const {'name': 'x'},
}) {
  return Op(
    opId: id,
    tableName: table,
    rowId: 'row-$id',
    opType: type,
    fieldsDiff: type == OpType.delete ? null : diff,
    hlc: Hlc(wallMillis: wall, counter: 0, nodeId: dev),
    deviceId: dev,
  );
}

void main() {
  late FakeSyncApiClient api;
  late InMemoryOutboxStore outbox;
  late InMemoryCursorStore cursors;
  late _RecordingApplier applier;
  late SyncStatusBus bus;
  late FixedClock clock;
  late SyncEngine engine;
  const dev = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

  setUp(() {
    api = FakeSyncApiClient();
    outbox = InMemoryOutboxStore();
    cursors = InMemoryCursorStore();
    applier = _RecordingApplier();
    bus = SyncStatusBus();
    clock = FixedClock(2_000_000_000_000);
    engine = SyncEngine(
      api: api,
      outbox: outbox,
      cursors: cursors,
      applier: applier,
      deviceId: dev,
      statusBus: bus,
      clock: clock,
    );
  });

  // SP-F-1 / SP-C-1
  test('happy path: push + pull cycle', () async {
    await outbox.enqueue(_localOp(id: '1', wall: 1_500_000_000_000, dev: dev));
    await outbox.enqueue(_localOp(id: '2', wall: 1_500_000_000_001, dev: dev));

    final result = await engine.run();

    expect(result.success, isTrue);
    expect(result.pushed, 2);
    expect(api.pushedBatches.single.map((o) => o.opId), ['1', '2']);
    expect(await outbox.depth(), 0);
    // Cursor advanced to server_hlc_high even though no foreign ops.
    expect(await cursors.readCursor(), isNotNull);
  });

  // SP-G-1 / SP-G-2: pull filters out caller's own ops
  test('pull filters out caller-authored ops', () async {
    // Seed remote op from another device.
    const otherDev = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
    api.seedRemote(_localOp(id: 'r1', wall: 1_500_000_000_000, dev: otherDev));
    final result = await engine.run();
    expect(result.pulled, 1);
    expect(applier.applied.single.opId, 'r1');
  });

  // SP-D-5: empty page still advances cursor
  test('empty pull advances cursor to server_hlc_high', () async {
    api.serverHlc = const Hlc(
      wallMillis: 1_500_000_000_000,
      counter: 5,
      nodeId: Hlc.serverNodeId,
    );
    await engine.run();
    final cursor = await cursors.readCursor();
    expect(cursor, isNotNull);
    expect(cursor!.wallMillis, 1_500_000_000_000);
  });

  // SP-G-3 / SP-G-4: concurrent calls share inflight future
  test('concurrent run() calls dedupe', () async {
    await outbox.enqueue(_localOp(id: '1', wall: 1_500_000_000_000, dev: dev));
    final f1 = engine.run();
    final f2 = engine.run();
    expect(identical(f1, f2), isTrue);
    await Future.wait([f1, f2]);
    expect(api.pushedBatches.length, 1, reason: 'no duplicate push');
  });

  // SP-I-6 (network class) — backoff on retryable errors
  test('network failure -> offline status, backoff scheduled', () async {
    api.programmedResponses.add(SyncException(SyncErrorKind.network));
    await outbox.enqueue(_localOp(id: '1', wall: 1_500_000_000_000, dev: dev));

    final result = await engine.run();

    expect(result.success, isFalse);
    expect(bus.current.status, SyncStatus.offline);
    expect(engine.nextBackoff, isNotNull);
    expect(engine.state, EngineState.backoff);
    // Outbox not drained — we'll retry next cycle.
    expect(await outbox.depth(), 1);
  });

  // SP-I-3: protocol version is non-recoverable
  test('protocol version mismatch -> failed status', () async {
    api.programmedResponses.add(
      SyncException(
        SyncErrorKind.protocolVersion,
        statusCode: 426,
        code: 'protocol_version',
      ),
    );
    await outbox.enqueue(_localOp(id: '1', wall: 1_500_000_000_000, dev: dev));

    final result = await engine.run();

    expect(result.success, isFalse);
    expect(bus.current.status, SyncStatus.failed);
    expect(engine.state, EngineState.halted);
  });

  // SP-I-5: Retry-After is honoured
  test(
    '429 with Retry-After -> backoff at least the requested delay',
    () async {
      api.programmedResponses.add(
        SyncException(
          SyncErrorKind.rateLimited,
          statusCode: 429,
          retryAfter: const Duration(seconds: 12),
        ),
      );
      await outbox.enqueue(
        _localOp(id: '1', wall: 1_500_000_000_000, dev: dev),
      );

      final result = await engine.run();

      expect(result.success, isFalse);
      expect(engine.nextBackoff!.inSeconds >= 12, isTrue);
    },
  );

  // SP-C-3: per-op rejection drops only that op
  test('per-op rejection drops the op + records sync_errors', () async {
    api.programmedResponses.add(
      PushResponse(
        accepted: 1,
        rejected: const [PushRejection(opId: 'bad', code: 'op_id_mutated')],
        serverHlcHigh: api.serverHlc,
        serverNow: DateTime.now(),
      ),
    );
    await outbox.enqueue(
      _localOp(id: 'bad', wall: 1_500_000_000_000, dev: dev),
    );
    await outbox.enqueue(_localOp(id: 'ok', wall: 1_500_000_000_001, dev: dev));

    final result = await engine.run();

    expect(result.success, isTrue);
    expect(await outbox.depth(), 0);
    expect(outbox.failures.single.opId, 'bad');
  });

  // SP-D-4: pagination drains all pages
  test('multi-page pull drains until has_more = false', () async {
    const otherDev = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
    for (var i = 0; i < 1500; i++) {
      api.seedRemote(
        _localOp(id: 'r$i', wall: 1_500_000_000_000 + i, dev: otherDev),
      );
    }
    await engine.run();
    expect(applier.applied.length, 1500);
  });

  // SP-J-3: cursor ahead of server is harmless
  test('cursor ahead of server returns no ops, no error', () async {
    await cursors.writeCursor(
      const Hlc(
        wallMillis: 9_999_999_999_000,
        counter: 0,
        nodeId: Hlc.serverNodeId,
      ),
    );
    final result = await engine.run();
    expect(result.success, isTrue);
    expect(result.pulled, 0);
  });

  // §7.1: stampHlc generates monotonic local ticks
  test('stampHlc produces monotonically increasing HLCs', () async {
    final a = await engine.stampHlc(overrideNowMillis: 1_500_000_000_000);
    final b = await engine.stampHlc(overrideNowMillis: 1_500_000_000_000);
    final c = await engine.stampHlc(overrideNowMillis: 1_500_000_000_001);
    expect(a < b, isTrue);
    expect(b < c, isTrue);
    expect(a.nodeId, dev);
  });

  test('successful run resets backoff', () async {
    api.programmedResponses.add(SyncException(SyncErrorKind.network));
    await engine.run();
    expect(engine.nextBackoff, isNotNull);
    api.programmedResponses.clear();
    final result = await engine.run();
    expect(result.success, isTrue);
    expect(engine.nextBackoff, isNull);
    expect(bus.current.status, SyncStatus.online);
  });
}
