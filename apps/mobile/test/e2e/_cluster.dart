import 'package:drift/drift.dart' show Variable;
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/clock.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/row_applier.dart';
import 'package:naviwealth/core/sync/sync_engine.dart';
import 'package:naviwealth/core/sync/sync_status.dart';
import 'package:naviwealth/core/sync/sync_table_registry.dart';

import '../core/persistence/test_database.dart';
import '../core/sync/_fake_api.dart';

/// One simulated device: a real in-memory Drift DB + the v2 SyncEngine.
///
/// Each device runs the production [RowApplier] / [DriftPendingRows] /
/// [DriftCursorStore] against its own database, so convergence is asserted
/// on the same code path the app uses. The harness drives time explicitly
/// via [advanceClock] so tests can model "30 s polling cadence" without
/// sleeping.
class VirtualDevice {
  VirtualDevice({
    required this.id,
    required this.api,
    int initialClockMillis = 1_700_000_000_000,
  }) : clock = FixedClock(initialClockMillis),
       db = makeTestDatabase(),
       statusBus = SyncStatusBus() {
    pending = DriftPendingRows(db);
    cursors = DriftCursorStore(db);
    final outbox = DriftOutboxStore(db);
    _outbox = outbox;
    engine = SyncEngine(
      api: api,
      pending: pending,
      cursors: cursors,
      applier: RowApplier(db),
      deviceId: id,
      statusBus: statusBus,
      clock: clock,
    );
  }

  final String id;
  final FakeSyncApiClient api;
  final FixedClock clock;
  final AppDatabase db;
  final SyncStatusBus statusBus;
  late final DriftPendingRows pending;
  late final DriftCursorStore cursors;
  late final DriftOutboxStore _outbox;
  late final SyncEngine engine;

  bool offline = false;

  /// Number of locally-dirty rows awaiting push.
  Future<int> pendingDepth() => pending.depth();

  /// Issue a local mutation: stamp an HLC, write the full row state to the
  /// local DB, queue a dirty pointer. Mirrors what a repository's `mutate`
  /// does — the UI returns immediately, sync runs later.
  Future<void> writeRow({
    required String table,
    required String rowId,
    required Map<String, Object?> columns,
    bool deleted = false,
  }) async {
    final hlc = await engine.stampHlc(overrideNowMillis: clock.nowMillis());
    final row = <String, Object?>{
      ...columns,
      'id': rowId,
      'hlc': hlc.toString(),
      'owner_user_id': columns['owner_user_id'] ?? 'user-1',
      'updated_at': clock.nowMillis() ~/ 1000,
      'updated_by_device': id,
      'deleted_at': deleted ? clock.nowMillis() ~/ 1000 : null,
    };
    await _writeLocal(table, rowId, row);
    await _outbox.enqueue(table: table, rowId: rowId);
  }

  /// Apply a full row-state to the local DB via INSERT OR REPLACE — the same
  /// write the [RowApplier] performs for pulled rows.
  Future<void> _writeLocal(
    String table,
    String rowId,
    Map<String, Object?> row,
  ) async {
    final pk = syncPrimaryKeyForTable(table);
    final ordered = <String, Object?>{...row};
    ordered[pk] = rowId;
    final cols = ordered.keys.toList(growable: false);
    final placeholders = List.filled(cols.length, '?').join(', ');
    await db.customStatement(
      'INSERT OR REPLACE INTO $table (${cols.join(', ')}) '
      'VALUES ($placeholders)',
      cols.map((c) => ordered[c]).toList(growable: false),
    );
  }

  /// Read the materialised state of a row, or `null` if absent.
  Future<Map<String, Object?>?> lookup(String table, String rowId) async {
    final pk = syncPrimaryKeyForTable(table);
    final row = await db
        .customSelect(
          'SELECT * FROM $table WHERE $pk = ?',
          variables: [Variable.withString(rowId)],
        )
        .getSingleOrNull();
    return row?.data;
  }

  /// True if a row exists and is not tombstoned.
  Future<bool> isVisible(String table, String rowId) async {
    final row = await lookup(table, rowId);
    return row != null && row['deleted_at'] == null;
  }

  /// Visible (non-tombstoned) row ids for a table.
  Future<List<String>> visibleIds(String table) async {
    final rows = await db
        .customSelect('SELECT id FROM $table WHERE deleted_at IS NULL')
        .get();
    return rows.map((r) => r.read<String>('id')).toList();
  }

  /// Run one push+pull cycle if online; no-op when offline.
  Future<SyncCycleResult?> tickSync() async {
    if (offline) return null;
    return engine.run();
  }

  /// Advance the device clock by [d].
  void advanceClock(Duration d) => clock.advance(d);

  Future<void> dispose() => db.close();
}

/// A cluster of virtual devices sharing one in-memory backend.
///
/// All devices push to / pull from the same [FakeSyncApiClient]; the pull
/// echo filter (`device_id != self`) keeps each device from seeing its own
/// writes — the same invariant as `apps/backend/src/routes/sync.rs`.
class SyncCluster {
  SyncCluster({int? initialClockMillis})
    : _initialClockMillis = initialClockMillis ?? 1_700_000_000_000 {
    api = FakeSyncApiClient();
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
  /// order — pass 1 uploads every device's backlog so the server has the
  /// union of all writes; pass 2 lets each device pull what its peers just
  /// published.
  Future<void> syncAll() async {
    for (final d in devices) {
      await d.tickSync();
    }
    for (final d in devices) {
      await d.tickSync();
    }
  }

  void advanceAllClocks(Duration d) {
    for (final dev in devices) {
      dev.advanceClock(d);
    }
  }

  Future<void> disposeAll() async {
    for (final d in devices) {
      await d.dispose();
    }
  }

  /// Snapshot a device's visible state for a table, keyed by row id with the
  /// LWW token (`hlc`) as the value — convergence compares these.
  Future<Map<String, String>> _snapshot(VirtualDevice d, String table) async {
    final rows = await d.db.customSelect('SELECT * FROM $table').get();
    final out = <String, String>{};
    for (final r in rows) {
      final data = r.data;
      final id = data['id'] as String;
      out[id] = data['deleted_at'] == null
          ? '${data['name']}@${data['hlc']}'
          : 'DEL@${data['hlc']}';
    }
    return out;
  }

  /// True when every device's materialised state for [table] is identical.
  Future<bool> isConverged(String table) async {
    if (devices.length < 2) return true;
    final ref = await _snapshot(devices.first, table);
    for (final d in devices.skip(1)) {
      final snap = await _snapshot(d, table);
      if (!_mapEquals(ref, snap)) return false;
    }
    return true;
  }
}

bool _mapEquals(Map<String, String> a, Map<String, String> b) {
  if (a.length != b.length) return false;
  for (final k in a.keys) {
    if (a[k] != b[k]) return false;
  }
  return true;
}
