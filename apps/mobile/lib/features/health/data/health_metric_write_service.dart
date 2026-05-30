/// HealthOS local write service.
///
/// Manual entry UI and HealthOS AI write tools share this path so sync
/// stamping, stable ids, units, and source attribution stay identical.
library;

import 'dart:convert';

import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';

import '../domain/health_metric.dart';
import '../domain/health_metric_kind.dart';
import 'health_metric_repository.dart';

class HealthMetricWriteService {
  HealthMetricWriteService({
    required HealthMetricRepository repository,
    required MutationStamper stamper,
  }) : _repository = repository,
       _stamper = stamper;

  final HealthMetricRepository _repository;
  final MutationStamper _stamper;

  Future<HealthMetric> recordBodyMeasurement({
    required HealthMetricKind kind,
    required double value,
    required DateTime capturedAt,
    String source = 'manual',
    String? note,
  }) async {
    if (kind != HealthMetricKind.weight && kind != HealthMetricKind.bodyFat) {
      throw ArgumentError.value(kind, 'kind', 'Only weight/bodyFat supported.');
    }
    if (!value.isFinite || value <= 0) {
      throw ArgumentError.value(value, 'value', 'Value must be positive.');
    }
    final normalizedValue = kind == HealthMetricKind.bodyFat && value > 1
        ? value / 100.0
        : value;
    if (kind == HealthMetricKind.bodyFat && normalizedValue > 1) {
      throw ArgumentError.value(value, 'value', 'Body fat must be 0-100%.');
    }

    final stamp = await _stamper.stamp();
    final at = capturedAt.toUtc();
    final payload = <String, Object?>{
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
    };
    final metric = HealthMetric(
      id: _manualMetricId(kind, at, stamp.ownerUserId),
      capturedAt: at,
      kind: kind,
      value: normalizedValue,
      unit: kind.defaultUnit,
      payloadJson: payload.isEmpty ? null : jsonEncode(payload),
      sourceDevice: source,
      sync: SyncMeta(
        ownerUserId: stamp.ownerUserId,
        updatedAt: stamp.now,
        updatedByDevice: stamp.deviceId,
        hlc: stamp.hlc,
      ),
    );
    await _repository.upsert(metric);
    return metric;
  }

  static String _manualMetricId(
    HealthMetricKind kind,
    DateTime capturedAt,
    String ownerUserId,
  ) {
    final day = capturedAt.toUtc().toIso8601String().substring(0, 10);
    // One manual value per kind/day/user. Same-day re-entry intentionally
    // replaces the row instead of creating noisy duplicates.
    return 'manual:${kind.wire}:$ownerUserId:$day';
  }
}
