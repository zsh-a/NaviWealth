import 'package:naviwealth/core/sync/clock.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/op.dart';
import 'package:naviwealth/core/sync/op_applier.dart';
import 'package:naviwealth/core/sync/sync_engine.dart';
import 'package:naviwealth/core/sync/sync_status.dart';
import 'package:naviwealth/data/domain/hlc.dart';

import '../core/sync/_fake_api.dart';

/// Materialised view of a single row inside a virtual device's local store.
class MaterialisedRow {
  MaterialisedRow({
    required this.payload,
    required this.lastHlc,
    this.deletedAt,
  });

  Map<String, Object?> payload;
  Hlc lastHlc;
  DateTime? deletedAt;

  bool get isDeleted => deletedAt != null;

  @override
  String toString() =>
      'Row(${isDeleted ? 'DEL ' : ''}$payload @ $lastHlc)';
}

/// Row-level LWW applier backed by an in-memory map.
///
/// Mirrors the server-side materialiser logic from
/// `apps/backend/src/sync/materialise.rs`: shadow ops with `op.hlc <= last_hlc`,
/// shallow-merge `fields_diff` for insert/update, retain payload but flip
/// `deleted_at` for tombstones, and clear `deleted_at` on resurrection.
class LwwInMemoryApplier implements OpApplier {
  final Map<String, Map<String, MaterialisedRow>> _tables = {};

  Map<String, MaterialisedRow> _table(String t) =>
      _tables.putIfAbsent(t, () => <String, MaterialisedRow>{});

  MaterialisedRow? lookup(String table, String rowId) =>
      _tables[table]?[rowId];

  /// Visible rows (not tombstoned) for a table.
  List<MaterialisedRow> list(String table) =>
      (_tables[table] ?? const <String, MaterialisedRow>{})
          .values
          .where((r) => !r.isDeleted)
          .toList();

  /// Snapshot keyed by `<table>/<rowId>` of the user-visible state
  /// (payload + tombstone flag).
  ///
  /// Convergence asserts the *materialised* state — not last_hlc, because
  /// authors keep their `client_hlc` on locally-written rows while peers
  /// apply `server_hlc` from the pull, and those are equal in ordering but
  /// not bit-identical (different `node_id`).
  Map<String, String> snapshot() {
    final out = <String, String>{};
    _tables.forEach((table, rows) {
      rows.forEach((rowId, row) {
        out['$table/$rowId'] = row.isDeleted ? 'DEL' : row.payload.toString();
      });
    });
    return out;
  }

  @override
  Future<void> applyAll(List<Op> ops) async {
    for (final op in ops) {
      _applyOne(op);
    }
  }

  /// Apply a single op locally — used by virtual devices to mirror what the
  /// repo layer does at write time (write the row first, queue the op).
  void applyLocal(Op op) => _applyOne(op);

  void _applyOne(Op op) {
    final table = _table(op.tableName);
    final cur = table[op.rowId];
    if (cur != null && op.hlc <= cur.lastHlc) {
      return; // shadowed
    }
    switch (op.opType) {
      case OpType.delete:
        table[op.rowId] = MaterialisedRow(
          payload: cur?.payload ?? <String, Object?>{},
          lastHlc: op.hlc,
          deletedAt: DateTime.fromMillisecondsSinceEpoch(
            op.hlc.wallMillis,
            isUtc: true,
          ),
        );
      case OpType.insert:
      case OpType.update:
        final base = cur?.payload ?? <String, Object?>{};
        final merged = <String, Object?>{...base, ...?op.fieldsDiff};
        table[op.rowId] = MaterialisedRow(
          payload: merged,
          lastHlc: op.hlc,
          deletedAt: null,
        );
    }
  }
}

/// One simulated device: SyncEngine + outbox + cursor + materialised store.
///
/// Holds all the moving parts a real device has. The harness drives time
/// explicitly via [advanceClock] so tests can model "30 s polling cadence",
/// "next morning", etc., without sleeping.
class VirtualDevice {
  VirtualDevice({
    required this.id,
    required this.api,
    int initialClockMillis = 1_700_000_000_000,
  }) : clock = FixedClock(initialClockMillis),
       outbox = InMemoryOutboxStore(),
       cursors = InMemoryCursorStore(),
       applier = LwwInMemoryApplier(),
       statusBus = SyncStatusBus() {
    engine = SyncEngine(
      api: api,
      outbox: outbox,
      cursors: cursors,
      applier: applier,
      deviceId: id,
      statusBus: statusBus,
      clock: clock,
    );
  }

  final String id;
  final FakeSyncApiClient api;
  final FixedClock clock;
  final InMemoryOutboxStore outbox;
  final InMemoryCursorStore cursors;
  final LwwInMemoryApplier applier;
  final SyncStatusBus statusBus;
  late final SyncEngine engine;

  bool offline = false;
  int _opCounter = 0;

  String _nextOpId() => '$id-op-${(++_opCounter).toString().padLeft(5, '0')}';

  /// Issue a local mutation: stamp HLC, write to the local store, queue the
  /// op for the next push. Mirrors what a repo's `mutate(...)` does in real
  /// life — UI returns immediately, sync runs later.
  Future<Op> writeRow({
    required String table,
    required String rowId,
    required OpType opType,
    Map<String, Object?>? fieldsDiff,
  }) async {
    final hlc = await engine.stampHlc(overrideNowMillis: clock.nowMillis());
    final op = Op(
      opId: _nextOpId(),
      tableName: table,
      rowId: rowId,
      opType: opType,
      fieldsDiff: opType == OpType.delete ? null : fieldsDiff,
      hlc: hlc,
      deviceId: id,
    );
    applier.applyLocal(op);
    await outbox.enqueue(op);
    return op;
  }

  /// Run one push+pull cycle if the device is online; no-op when offline.
  Future<SyncCycleResult?> tickSync() async {
    if (offline) return null;
    return engine.run();
  }

  /// Advance the device clock by [d] (used to model the 30 s polling cadence
  /// or longer offline windows).
  void advanceClock(Duration d) => clock.advance(d);
}

/// A cluster of virtual devices sharing one in-memory backend.
///
/// All devices pull from / push to the same [FakeSyncApiClient]; devices are
/// distinguished by `device_id` and the pull filter (`device_id != self`)
/// keeps each device from seeing its own echoes — same invariant as
/// `apps/backend/src/routes/sync.rs` `pull_inner`.
class SyncCluster {
  SyncCluster({int? initialClockMillis}) : _initialClockMillis =
            initialClockMillis ?? 1_700_000_000_000 {
    api = FakeSyncApiClient()
      ..serverHlc = Hlc(
        wallMillis: _initialClockMillis - 1000,
        counter: 0,
        nodeId: Hlc.serverNodeId,
      );
  }

  final int _initialClockMillis;
  late final FakeSyncApiClient api;
  final List<VirtualDevice> devices = [];

  VirtualDevice addDevice(String id) {
    final d = VirtualDevice(
      id: id,
      api: api,
      initialClockMillis: _initialClockMillis,
    );
    devices.add(d);
    return d;
  }

  /// Drive a sync round: every online device runs one push+pull cycle.
  ///
  /// Two passes guarantee full convergence regardless of registration
  /// order — pass 1 lets every device upload its backlog so the server has
  /// the union of all writes; pass 2 lets every device pull what its peers
  /// just published.
  Future<void> syncAll() async {
    for (final d in devices) {
      await d.tickSync();
    }
    for (final d in devices) {
      await d.tickSync();
    }
  }

  /// Advance every device's clock — useful to simulate "wait 30 s" without
  /// blocking the test thread.
  void advanceAllClocks(Duration d) {
    for (final dev in devices) {
      dev.advanceClock(d);
    }
  }

  /// True when every device's materialised state is identical.
  bool isConverged() {
    if (devices.length < 2) return true;
    final ref = devices.first.applier.snapshot();
    for (final d in devices.skip(1)) {
      if (!_mapEquals(ref, d.applier.snapshot())) return false;
    }
    return true;
  }

  /// Pretty-print divergence between two devices for failing assertions.
  String describeDivergence(VirtualDevice a, VirtualDevice b) {
    final sa = a.applier.snapshot();
    final sb = b.applier.snapshot();
    final keys = {...sa.keys, ...sb.keys}.toList()..sort();
    final lines = <String>['device ${a.id} vs ${b.id}:'];
    for (final k in keys) {
      if (sa[k] != sb[k]) {
        lines.add('  $k: ${sa[k]}  !=  ${sb[k]}');
      }
    }
    return lines.join('\n');
  }
}

bool _mapEquals(Map<String, String> a, Map<String, String> b) {
  if (a.length != b.length) return false;
  for (final k in a.keys) {
    if (a[k] != b[k]) return false;
  }
  return true;
}
