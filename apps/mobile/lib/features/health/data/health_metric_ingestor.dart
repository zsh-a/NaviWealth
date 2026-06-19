/// Shared HealthOS ingestion pipeline.
///
/// Platform adapters and Garmin both produce unstamped metric rows. This class
/// owns idempotency, sync stamping, and repository writes so every source has
/// the same conflict/outbox behavior.
library;

import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';

import '../domain/health_metric.dart';
import '../domain/health_metric_kind.dart';
import 'health_metric_repository.dart';

class RawHealthMetric {
  const RawHealthMetric({
    required this.id,
    required this.capturedAt,
    required this.kind,
    required this.value,
    String? unit,
    this.payloadJson,
    this.sourceDevice,
  }) : unit = unit ?? '';

  final String id;
  final DateTime capturedAt;
  final HealthMetricKind kind;
  final double value;
  final String unit;
  final String? payloadJson;
  final String? sourceDevice;

  HealthMetric toMetric({required SyncMeta sync}) => HealthMetric(
    id: id,
    capturedAt: capturedAt,
    kind: kind,
    value: value,
    unit: unit.isEmpty ? kind.defaultUnit : unit,
    payloadJson: payloadJson,
    sourceDevice: sourceDevice,
    sync: sync,
  );
}

class HealthIngestResult {
  const HealthIngestResult({
    required this.total,
    required this.upserted,
    required this.unchanged,
  });

  final int total;
  final int upserted;
  final int unchanged;
}

class HealthMetricIngestor {
  HealthMetricIngestor({
    required HealthMetricRepository repository,
    required MutationStamper stamper,
  }) : _repo = repository,
       _stamper = stamper;

  final HealthMetricRepository _repo;
  final MutationStamper _stamper;

  Future<HealthIngestResult> ingestRaw(Iterable<RawHealthMetric> rows) async {
    final batch = rows.toList(growable: false);
    if (batch.isEmpty) {
      return const HealthIngestResult(total: 0, upserted: 0, unchanged: 0);
    }

    final existingById = await _repo.findByIds(batch.map((r) => r.id));
    final writes = <HealthMetric>[];
    var unchanged = 0;

    for (final row in batch) {
      final existing = existingById[row.id];
      if (existing != null && _payloadEquivalentRaw(existing, row)) {
        unchanged++;
        continue;
      }
      final stamped = row.toMetric(sync: await _stampMeta());
      writes.add(stamped);
      existingById[row.id] = stamped;
    }

    await _repo.upsertAll(writes);
    return HealthIngestResult(
      total: batch.length,
      upserted: writes.length,
      unchanged: unchanged,
    );
  }

  Future<HealthIngestResult> ingest(Iterable<HealthMetric> rows) async {
    final batch = rows.toList(growable: false);
    if (batch.isEmpty) {
      return const HealthIngestResult(total: 0, upserted: 0, unchanged: 0);
    }

    final existingById = await _repo.findByIds(batch.map((r) => r.id));
    final writes = <HealthMetric>[];
    var unchanged = 0;

    for (final row in batch) {
      final existing = existingById[row.id];
      if (existing != null && _payloadEquivalent(existing, row)) {
        unchanged++;
        continue;
      }
      final stamped = await _stamp(row);
      writes.add(stamped);
      existingById[row.id] = stamped;
    }

    await _repo.upsertAll(writes);
    return HealthIngestResult(
      total: batch.length,
      upserted: writes.length,
      unchanged: unchanged,
    );
  }

  Future<HealthMetric> _stamp(HealthMetric unstamped) async {
    return unstamped.copyWith(sync: await _stampMeta());
  }

  Future<SyncMeta> _stampMeta() async {
    final stamp = await _stamper.stamp();
    return SyncMeta(
      ownerUserId: stamp.ownerUserId,
      updatedAt: stamp.now,
      updatedByDevice: stamp.deviceId,
      hlc: stamp.hlc,
    );
  }

  bool _payloadEquivalent(HealthMetric a, HealthMetric b) {
    return a.kind == b.kind &&
        a.capturedAt.isAtSameMomentAs(b.capturedAt) &&
        a.value == b.value &&
        a.unit == b.unit &&
        a.payloadJson == b.payloadJson &&
        a.sourceDevice == b.sourceDevice;
  }

  bool _payloadEquivalentRaw(HealthMetric a, RawHealthMetric b) {
    return a.kind == b.kind &&
        a.capturedAt.isAtSameMomentAs(b.capturedAt) &&
        a.value == b.value &&
        a.unit == (b.unit.isEmpty ? b.kind.defaultUnit : b.unit) &&
        a.payloadJson == b.payloadJson &&
        a.sourceDevice == b.sourceDevice;
  }
}
