/// Shared HealthOS ingestion pipeline.
///
/// Platform adapters and Garmin both produce unstamped metric rows. This class
/// owns idempotency, sync stamping, and repository writes so every source has
/// the same conflict/outbox behavior.
library;

import 'package:naviwealth/core/sync/hlc.dart';
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

  HealthMetric toUnstamped() => HealthMetric(
    id: id,
    capturedAt: capturedAt,
    kind: kind,
    value: value,
    unit: unit.isEmpty ? kind.defaultUnit : unit,
    payloadJson: payloadJson,
    sourceDevice: sourceDevice,
    sync: _placeholderSync,
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

  Future<HealthIngestResult> ingestRaw(Iterable<RawHealthMetric> rows) {
    return ingest(rows.map((r) => r.toUnstamped()));
  }

  Future<HealthIngestResult> ingest(Iterable<HealthMetric> rows) async {
    var total = 0;
    var upserted = 0;
    var unchanged = 0;

    for (final row in rows) {
      total++;
      final result = await _upsertIfChanged(row);
      result == _WriteOutcome.upserted ? upserted++ : unchanged++;
    }

    return HealthIngestResult(
      total: total,
      upserted: upserted,
      unchanged: unchanged,
    );
  }

  Future<_WriteOutcome> _upsertIfChanged(HealthMetric unstamped) async {
    final existing = await _repo.findById(unstamped.id);
    if (existing != null && _payloadEquivalent(existing, unstamped)) {
      return _WriteOutcome.unchanged;
    }
    final stamp = await _stamper.stamp();
    final stamped = unstamped.copyWith(
      sync: SyncMeta(
        ownerUserId: stamp.ownerUserId,
        updatedAt: stamp.now,
        updatedByDevice: stamp.deviceId,
        hlc: stamp.hlc,
      ),
    );
    await _repo.upsert(stamped);
    return _WriteOutcome.upserted;
  }

  bool _payloadEquivalent(HealthMetric a, HealthMetric b) {
    return a.kind == b.kind &&
        a.capturedAt.isAtSameMomentAs(b.capturedAt) &&
        a.value == b.value &&
        a.unit == b.unit &&
        a.payloadJson == b.payloadJson &&
        a.sourceDevice == b.sourceDevice;
  }
}

final SyncMeta _placeholderSync = SyncMeta(
  ownerUserId: '',
  updatedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
  updatedByDevice: '',
  hlc: Hlc.zero('placeholder'),
);

enum _WriteOutcome { upserted, unchanged }
