/// HealthOS read / write API (`docs/healthos-domain.md` §3, D-2.1).
///
/// Thin Drift wrapper over the `health_metrics` table. The caller is
/// responsible for stamping sync metadata — the platform adapter in
/// D-2.2 (HealthKit / Health Connect) and the AI tools in D-2.4 supply
/// it. Keeping the stamping out of this class lets D-2.1 ship without
/// dragging the Finance-side `MutationStamper` (which lives under
/// `features/finance/data/repositories/`) across the domain boundary;
/// the stamper is expected to move to `core/sync/` in a follow-up.
///
/// Known cross-feature import (northstar §2.4): `SyncMeta` + `Hlc`
/// currently live under `features/finance/data/domain/`. Health rows
/// reuse them because the sync envelope is genuinely cross-domain
/// (`docs/lifeos-shell.md` §8 row-state). When those types relocate to
/// `core/sync/`, this import can be cleaned up.
library;

import 'package:drift/drift.dart' hide Column;
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/op_outbox.dart';
import 'package:naviwealth/features/finance/data/domain/sync_meta.dart';

import '../domain/health_metric.dart';
import '../domain/health_metric_kind.dart';

class HealthMetricRepository {
  HealthMetricRepository({required AppDatabase db, required OutboxStore outbox})
    : _db = db,
      _outbox = outbox;

  final AppDatabase _db;
  final OutboxStore _outbox;

  static const String _tableName = 'health_metrics';

  // ---------- Reads ----------

  /// Live stream of every non-deleted metric for [ownerUserId] of the
  /// given [kind], newest first. Caller supplies a [limit] so the
  /// watcher doesn't pump unbounded history into a UI build.
  Stream<List<HealthMetric>> watchRecent({
    required String ownerUserId,
    required HealthMetricKind kind,
    int limit = 90,
  }) {
    final query = _db.select(_db.healthMetrics)
      ..where((t) => t.ownerUserId.equals(ownerUserId))
      ..where((t) => t.kind.equals(kind.wire))
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([
        (t) => OrderingTerm(
          expression: t.capturedAt,
          mode: OrderingMode.desc,
        ),
      ])
      ..limit(limit);
    return query.watch().map((rows) => rows.map(_fromRow).toList());
  }

  /// One-shot read for [ownerUserId] + [kind], newest first.
  Future<List<HealthMetric>> listByKind({
    required String ownerUserId,
    required HealthMetricKind kind,
    int limit = 90,
  }) async {
    final query = _db.select(_db.healthMetrics)
      ..where((t) => t.ownerUserId.equals(ownerUserId))
      ..where((t) => t.kind.equals(kind.wire))
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([
        (t) => OrderingTerm(
          expression: t.capturedAt,
          mode: OrderingMode.desc,
        ),
      ])
      ..limit(limit);
    final rows = await query.get();
    return rows.map(_fromRow).toList();
  }

  Future<HealthMetric?> findById(String id) async {
    final row = await (_db.select(
      _db.healthMetrics,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null ? null : _fromRow(row);
  }

  // ---------- Writes ----------

  /// Insert (or replace, keyed by [HealthMetric.id]) [metric] and
  /// enqueue it in the sync outbox. The caller has already stamped
  /// [HealthMetric.sync] with a fresh HLC + owner + device id.
  Future<void> upsert(HealthMetric metric) async {
    final companion = HealthMetricsCompanion.insert(
      id: metric.id,
      capturedAt: metric.capturedAt,
      kind: metric.kind.wire,
      value: metric.value,
      unit: metric.unit,
      payloadJson: Value(metric.payloadJson),
      sourceDevice: Value(metric.sourceDevice),
      ownerUserId: metric.sync.ownerUserId,
      updatedAt: metric.sync.updatedAt,
      updatedByDevice: metric.sync.updatedByDevice,
      hlc: metric.sync.hlc,
      deletedAt: Value(metric.sync.deletedAt),
    );
    await _db.transaction(() async {
      await _db
          .into(_db.healthMetrics)
          .insert(companion, mode: InsertMode.insertOrReplace);
      await _outbox.enqueue(table: _tableName, rowId: metric.id);
    });
  }

  // ---------- Helpers ----------

  HealthMetric _fromRow(HealthMetricRow row) => HealthMetric(
    id: row.id,
    capturedAt: row.capturedAt,
    kind: HealthMetricKindX.parse(row.kind),
    value: row.value,
    unit: row.unit,
    payloadJson: row.payloadJson,
    sourceDevice: row.sourceDevice,
    sync: SyncMeta(
      ownerUserId: row.ownerUserId,
      updatedAt: row.updatedAt,
      updatedByDevice: row.updatedByDevice,
      hlc: row.hlc,
      deletedAt: row.deletedAt,
    ),
  );
}
