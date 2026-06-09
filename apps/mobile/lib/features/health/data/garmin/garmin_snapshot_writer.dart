/// Writes Rust `HealthSnapshot` JSON into local Drift database.
///
/// Reuses the same idempotent `_upsertIfChanged` pattern as
/// `HealthSyncService` — unchanged rows don't bump HLC or outbox.
library;

import 'dart:convert';

import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';

import '../../domain/health_metric.dart';
import '../../domain/health_metric_kind.dart';
import '../health_metric_repository.dart';

/// Outcome of writing one snapshot to Drift.
class GarminWriteResult {
  const GarminWriteResult({
    required this.upserted,
    required this.unchanged,
    this.errors = const [],
  });

  final int upserted;
  final int unchanged;
  final List<String> errors;

  int get total => upserted + unchanged;
  bool get ok => errors.isEmpty;
}

/// Placeholder sync meta — replaced by the stamper only on actual writes.
final SyncMeta _placeholderSync = SyncMeta(
  ownerUserId: '',
  updatedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
  updatedByDevice: '',
  hlc: Hlc.zero('placeholder'),
);

/// Writes a normalized HealthSnapshot (from Rust) into the local Drift DB.
class GarminSnapshotWriter {
  GarminSnapshotWriter({
    required HealthMetricRepository repository,
    required MutationStamper stamper,
  })  : _repo = repository,
        _stamper = stamper;

  final HealthMetricRepository _repo;
  final MutationStamper _stamper;

  /// Write a Rust HealthSnapshot JSON into the local database.
  ///
  /// Each metric is upserted idempotently — unchanged rows produce no
  /// outbox work.
  Future<GarminWriteResult> writeSnapshotJson(String snapshotJson) async {
    final json = jsonDecode(snapshotJson) as Map<String, dynamic>;
    return writeSnapshotMap(json);
  }

  /// Write a parsed snapshot map into the local database.
  Future<GarminWriteResult> writeSnapshotMap(
    Map<String, dynamic> snapshot,
  ) async {
    var upserted = 0;
    var unchanged = 0;
    final errors = <String>[];

    // Steps
    for (final item in _list(snapshot, 'steps')) {
      final result = await _upsertDaily(item, HealthMetricKind.stepsDaily);
      result ? upserted++ : unchanged++;
    }

    // Sleep sessions
    for (final item in _list(snapshot, 'sleep_sessions')) {
      try {
        final metric = _sleepMetric(item);
        final changed = await _upsertIfChanged(metric);
        changed ? upserted++ : unchanged++;
      } catch (e) {
        errors.add('sleep: $e');
      }
    }

    // Resting HR
    for (final item in _list(snapshot, 'resting_hr')) {
      final result = await _upsertDaily(item, HealthMetricKind.rhrDaily);
      result ? upserted++ : unchanged++;
    }

    // HRV
    for (final item in _list(snapshot, 'hrv')) {
      final result = await _upsertDaily(item, HealthMetricKind.hrvDaily);
      result ? upserted++ : unchanged++;
    }

    // Heart rate
    for (final item in _list(snapshot, 'heart_rate')) {
      final result = await _upsertDaily(item, HealthMetricKind.heartRateDaily);
      result ? upserted++ : unchanged++;
    }

    // Active energy
    for (final item in _list(snapshot, 'active_energy')) {
      final result =
          await _upsertDaily(item, HealthMetricKind.activeEnergyDaily);
      result ? upserted++ : unchanged++;
    }

    // VO2 max
    for (final item in _list(snapshot, 'vo2_max')) {
      final result = await _upsertDaily(item, HealthMetricKind.vo2Max);
      result ? upserted++ : unchanged++;
    }

    // Weight
    for (final item in _list(snapshot, 'weight')) {
      try {
        final metric = _pointMetric(item, HealthMetricKind.weight);
        final changed = await _upsertIfChanged(metric);
        changed ? upserted++ : unchanged++;
      } catch (e) {
        errors.add('weight: $e');
      }
    }

    // Body fat
    for (final item in _list(snapshot, 'body_fat')) {
      try {
        final metric = _pointMetric(item, HealthMetricKind.bodyFat);
        final changed = await _upsertIfChanged(metric);
        changed ? upserted++ : unchanged++;
      } catch (e) {
        errors.add('body_fat: $e');
      }
    }

    // Body battery — daily summary with payload_json detail
    for (final item in _list(snapshot, 'body_battery')) {
      try {
        final metric = _bodyBatteryMetric(item);
        final changed = await _upsertIfChanged(metric);
        changed ? upserted++ : unchanged++;
      } catch (e) {
        errors.add('body_battery: $e');
      }
    }

    // Stress — daily average level
    for (final item in _list(snapshot, 'stress')) {
      try {
        final metric = _stressMetric(item);
        final changed = await _upsertIfChanged(metric);
        changed ? upserted++ : unchanged++;
      } catch (e) {
        errors.add('stress: $e');
      }
    }

    return GarminWriteResult(
      upserted: upserted,
      unchanged: unchanged,
      errors: errors,
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  List<Map<String, dynamic>> _list(Map<String, dynamic> json, String key) {
    final raw = json[key];
    if (raw is! List) return const [];
    return raw.whereType<Map<String, dynamic>>().toList();
  }

  /// Upsert a DailyMetric-shaped item. Returns true if the row changed.
  Future<bool> _upsertDaily(
    Map<String, dynamic> item,
    HealthMetricKind kind,
  ) async {
    final id = item['id'] as String?;
    final dateStr = item['date'] as String?;
    final value = (item['value'] as num?)?.toDouble();
    final unit = item['unit'] as String? ?? kind.defaultUnit;
    final source = item['source_device'] as String?;

    if (id == null || dateStr == null || value == null) return false;

    final date = DateTime.parse(dateStr);
    final metric = HealthMetric(
      id: id,
      capturedAt: date,
      kind: kind,
      value: value,
      unit: unit,
      sourceDevice: source,
      sync: _placeholderSync,
    );
    return _upsertIfChanged(metric);
  }

  HealthMetric _sleepMetric(Map<String, dynamic> item) {
    return HealthMetric(
      id: item['id'] as String,
      capturedAt: DateTime.parse(item['started_at'] as String),
      kind: HealthMetricKind.sleepSession,
      value: (item['duration_seconds'] as num).toDouble(),
      unit: HealthMetricKind.sleepSession.defaultUnit,
      payloadJson: item['stage_histogram_json'] as String?,
      sourceDevice: item['source_device'] as String?,
      sync: _placeholderSync,
    );
  }

  HealthMetric _pointMetric(Map<String, dynamic> item, HealthMetricKind kind) {
    return HealthMetric(
      id: item['id'] as String,
      capturedAt: DateTime.parse(item['measured_at'] as String),
      kind: kind,
      value: (item['value'] as num).toDouble(),
      unit: item['unit'] as String? ?? kind.defaultUnit,
      sourceDevice: item['source_device'] as String?,
      sync: _placeholderSync,
    );
  }

  /// Body Battery → daily metric with payload_json detail.
  HealthMetric _bodyBatteryMetric(Map<String, dynamic> item) {
    final date = DateTime.parse(item['date'] as String);
    final min = item['min'] as int? ?? 0;
    final max = item['max'] as int? ?? 0;
    final charged = item['charged'] as int? ?? 0;
    final drained = item['drained'] as int? ?? 0;

    return HealthMetric(
      id: item['id'] as String,
      capturedAt: date,
      kind: HealthMetricKind.bodyBatteryDaily,
      value: max.toDouble(),
      unit: HealthMetricKind.bodyBatteryDaily.defaultUnit,
      payloadJson: jsonEncode({
        'min': min,
        'max': max,
        'charged': charged,
        'drained': drained,
      }),
      sourceDevice: item['source_device'] as String? ?? 'garmin',
      sync: _placeholderSync,
    );
  }

  /// Stress → daily average metric.
  HealthMetric _stressMetric(Map<String, dynamic> item) {
    final id = item['id'] as String?;
    final dateStr = item['date'] as String?;
    final value = (item['value'] as num?)?.toDouble();
    final source = item['source_device'] as String?;

    if (id == null || dateStr == null || value == null) {
      throw ArgumentError('Missing required stress fields');
    }

    return HealthMetric(
      id: id,
      capturedAt: DateTime.parse(dateStr),
      kind: HealthMetricKind.stressDaily,
      value: value,
      unit: HealthMetricKind.stressDaily.defaultUnit,
      sourceDevice: source,
      sync: _placeholderSync,
    );
  }

  /// Idempotent upsert — only writes if data changed.
  Future<bool> _upsertIfChanged(HealthMetric unstamped) async {
    final existing = await _repo.findById(unstamped.id);
    if (existing != null && _payloadEquivalent(existing, unstamped)) {
      return false;
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
    return true;
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
