/// HealthOS read / write API (`docs/domains/healthos-domain.md` §3, D-2.1).
///
/// Thin Drift wrapper over the `health_metrics` table. The caller is
/// responsible for stamping sync metadata via the cross-domain
/// `mutationStamperProvider` in `core/sync/mutation_context.dart`; the
/// platform adapter in D-2.2 (HealthKit / Health Connect) supplies
/// the stamp on insert.
library;

import 'package:drift/drift.dart' hide Column;
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/op_outbox.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';

import '../domain/health_metric.dart';
import '../domain/health_metric_kind.dart';
import 'health_metric_source.dart';

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
        (t) => OrderingTerm(expression: t.capturedAt, mode: OrderingMode.desc),
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
        (t) => OrderingTerm(expression: t.capturedAt, mode: OrderingMode.desc),
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

  Future<Map<String, HealthMetric>> findByIds(Iterable<String> ids) async {
    final uniqueIds = ids.toSet();
    if (uniqueIds.isEmpty) return const <String, HealthMetric>{};
    final rows = await (_db.select(
      _db.healthMetrics,
    )..where((t) => t.id.isIn(uniqueIds))).get();
    return <String, HealthMetric>{
      for (final row in rows) row.id: _fromRow(row),
    };
  }

  /// Batch read: fetch rows for multiple [kinds] in a single query.
  /// Returns a map of kind → rows (newest-first, per-kind [limit]).
  Future<Map<HealthMetricKind, List<HealthMetric>>> listByKinds({
    required String ownerUserId,
    required Set<HealthMetricKind> kinds,
    int limit = 90,
  }) async {
    if (kinds.isEmpty) return const {};
    final kindWires = kinds.map((k) => k.wire).toList();
    final query = _db.select(_db.healthMetrics)
      ..where((t) => t.ownerUserId.equals(ownerUserId))
      ..where((t) => t.kind.isIn(kindWires))
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([
        (t) => OrderingTerm(expression: t.capturedAt, mode: OrderingMode.desc),
      ])
      ..limit(limit * kinds.length);
    final rows = await query.get();
    final metrics = rows.map(_fromRow).toList();

    // Group by kind, preserving newest-first order, cap per kind.
    final result = <HealthMetricKind, List<HealthMetric>>{};
    for (final kind in kinds) {
      result[kind] = [];
    }
    for (final m in metrics) {
      final list = result[m.kind];
      if (list != null && list.length < limit) {
        list.add(m);
      }
    }
    return result;
  }

  // ---------- Writes ----------

  /// Insert (or replace, keyed by [HealthMetric.id]) [metric] and
  /// enqueue it in the sync outbox. The caller has already stamped
  /// [HealthMetric.sync] with a fresh HLC + owner + device id.
  Future<void> upsert(HealthMetric metric) async {
    await upsertAll([metric]);
  }

  /// Insert (or replace) every metric and enqueue one sync dirty pointer
  /// for each written row. The list order is preserved so callers that
  /// intentionally submit multiple corrections for the same id retain
  /// last-write-wins behavior.
  Future<void> upsertAll(Iterable<HealthMetric> metrics) async {
    final batch = metrics.toList(growable: false);
    if (batch.isEmpty) return;
    await _db.transaction(() async {
      for (final metric in batch) {
        await _db
            .into(_db.healthMetrics)
            .insert(_companionFor(metric), mode: InsertMode.insertOrReplace);
        await _outbox.enqueue(table: _tableName, rowId: metric.id);
      }
    });
  }

  HealthMetricsCompanion _companionFor(HealthMetric metric) {
    final companion = HealthMetricsCompanion.insert(
      id: metric.id,
      capturedAt: metric.capturedAt,
      kind: metric.kind.wire,
      value: metric.value,
      unit: metric.unit,
      payloadJson: Value(metric.payloadJson),
      sourceDevice: Value(metric.sourceDevice),
      sourceId: Value(sourceForHealthMetric(metric).id),
      ownerUserId: metric.sync.ownerUserId,
      updatedAt: metric.sync.updatedAt,
      updatedByDevice: metric.sync.updatedByDevice,
      hlc: metric.sync.hlc,
      deletedAt: Value(metric.sync.deletedAt),
    );
    return companion;
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
