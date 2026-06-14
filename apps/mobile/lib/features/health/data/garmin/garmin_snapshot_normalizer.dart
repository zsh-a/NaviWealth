/// Normalizes the Garmin Rust `HealthSnapshot` into HealthOS raw metric rows.
///
/// Endpoint probes and diagnostic JSON are intentionally kept out of this
/// production writer. Garmin-specific endpoint parsing belongs in the native
/// Garmin mapper; Dart consumes one canonical provider snapshot shape.
library;

import 'dart:convert';

import '../../domain/health_metric_kind.dart';
import '../health_metric_ingestor.dart';

class GarminMetricBatch {
  const GarminMetricBatch({
    required this.rows,
    required this.errors,
    required this.countsByKind,
  });

  final List<RawHealthMetric> rows;
  final List<String> errors;
  final Map<HealthMetricKind, int> countsByKind;
}

class GarminSnapshotNormalizer {
  const GarminSnapshotNormalizer();

  GarminMetricBatch normalize(Map<String, dynamic> snapshot) {
    final builder = _GarminMetricBatchBuilder();

    _addDailyList(builder, snapshot, 'steps', HealthMetricKind.stepsDaily);
    _addSleepList(builder, snapshot, 'sleep_sessions');
    _addActivityList(builder, snapshot, 'activities');
    _addActivityList(builder, snapshot, 'workouts');
    _addDailyList(builder, snapshot, 'resting_hr', HealthMetricKind.rhrDaily);
    _addDailyList(builder, snapshot, 'hrv', HealthMetricKind.hrvDaily);
    _addDailyList(
      builder,
      snapshot,
      'heart_rate',
      HealthMetricKind.heartRateDaily,
    );
    _addDailyList(
      builder,
      snapshot,
      'active_energy',
      HealthMetricKind.activeEnergyDaily,
    );
    _addDailyList(
      builder,
      snapshot,
      'distance_walking_running',
      HealthMetricKind.distanceWalkingRunningDaily,
    );
    _addDailyList(
      builder,
      snapshot,
      'total_energy',
      HealthMetricKind.totalEnergyDaily,
    );
    _addDailyList(builder, snapshot, 'vo2_max', HealthMetricKind.vo2Max);
    _addPointList(builder, snapshot, 'weight', HealthMetricKind.weight);
    _addPointList(builder, snapshot, 'body_fat', HealthMetricKind.bodyFat);
    _addBodyBatteryList(builder, snapshot, 'body_battery');
    _addDailyList(builder, snapshot, 'stress', HealthMetricKind.stressDaily);
    _addDailyList(
      builder,
      snapshot,
      'floors_climbed',
      HealthMetricKind.floorsClimbedDaily,
    );
    _addDailyList(
      builder,
      snapshot,
      'respiratory_rate',
      HealthMetricKind.respiratoryRateDaily,
    );
    _addDailyList(
      builder,
      snapshot,
      'training_load',
      HealthMetricKind.trainingLoadDaily,
    );
    _addDailyList(
      builder,
      snapshot,
      'training_effect',
      HealthMetricKind.trainingEffectDaily,
    );
    _addDailyList(builder, snapshot, 'spo2', HealthMetricKind.spo2Daily);

    return GarminMetricBatch(
      rows: builder.rows,
      errors: builder.errors,
      countsByKind: builder.countsByKind,
    );
  }

  void _addDailyList(
    _GarminMetricBatchBuilder builder,
    Map<String, dynamic> snapshot,
    String key,
    HealthMetricKind kind,
  ) {
    for (final item in _mapList(snapshot[key])) {
      builder.addDaily(
        id: _string(item['id']),
        date: _string(item['date']),
        kind: kind,
        value: _number(item['value']),
        unit: _string(item['unit']),
        sourceDevice: _string(item['source_device']),
      );
    }
  }

  void _addPointList(
    _GarminMetricBatchBuilder builder,
    Map<String, dynamic> snapshot,
    String key,
    HealthMetricKind kind,
  ) {
    for (final item in _mapList(snapshot[key])) {
      final measuredAt = _parseInstant(_string(item['measured_at']));
      final id = _string(item['id']);
      final value = _number(item['value']);
      if (id == null || measuredAt == null || value == null) continue;
      builder.add(
        RawHealthMetric(
          id: id,
          capturedAt: measuredAt,
          kind: kind,
          value: value,
          unit: _string(item['unit']) ?? kind.defaultUnit,
          sourceDevice: _string(item['source_device']),
        ),
      );
    }
  }

  void _addSleepList(
    _GarminMetricBatchBuilder builder,
    Map<String, dynamic> snapshot,
    String key,
  ) {
    for (final item in _mapList(snapshot[key])) {
      final id = _string(item['id']);
      final startedAt = _parseInstant(_string(item['started_at']));
      final duration = _number(item['duration_seconds']);
      if (id == null || startedAt == null || duration == null) continue;
      builder.add(
        RawHealthMetric(
          id: id,
          capturedAt: startedAt,
          kind: HealthMetricKind.sleepSession,
          value: duration,
          unit: HealthMetricKind.sleepSession.defaultUnit,
          payloadJson: _string(item['stage_histogram_json']),
          sourceDevice: _string(item['source_device']),
        ),
      );
    }
  }

  void _addActivityList(
    _GarminMetricBatchBuilder builder,
    Map<String, dynamic> snapshot,
    String key,
  ) {
    for (final item in _mapList(snapshot[key])) {
      final id = _string(item['id']);
      final startedAt = _parseInstant(_string(item['started_at']));
      final duration = _number(item['duration_seconds']);
      if (id == null || startedAt == null || duration == null) continue;

      final payload = <String, Object?>{};
      final activityType = _string(item['activity_type']);
      if (activityType != null) payload['activity_type'] = activityType;
      if (item['total_energy_kcal'] != null) {
        payload['totalEnergyKcal'] = item['total_energy_kcal'];
      }
      if (item['total_distance_meters'] != null) {
        payload['totalDistanceMeters'] = item['total_distance_meters'];
      }

      builder.add(
        RawHealthMetric(
          id: id,
          capturedAt: startedAt,
          kind: HealthMetricKind.workoutSession,
          value: duration,
          unit: HealthMetricKind.workoutSession.defaultUnit,
          payloadJson: payload.isEmpty ? null : jsonEncode(payload),
          sourceDevice: _string(item['source_device']),
        ),
      );
    }
  }

  void _addBodyBatteryList(
    _GarminMetricBatchBuilder builder,
    Map<String, dynamic> snapshot,
    String key,
  ) {
    for (final item in _mapList(snapshot[key])) {
      final date = _string(item['date']);
      final id = _string(item['id']);
      if (date == null || id == null) continue;
      final min = _int(item['min']) ?? 0;
      final max = _int(item['max']) ?? 0;
      final charged = _int(item['charged']) ?? 0;
      final drained = _int(item['drained']) ?? 0;
      builder.add(
        RawHealthMetric(
          id: id,
          capturedAt: _parseDayStart(date),
          kind: HealthMetricKind.bodyBatteryDaily,
          value: max.toDouble(),
          unit: HealthMetricKind.bodyBatteryDaily.defaultUnit,
          payloadJson: jsonEncode({
            'min': min,
            'max': max,
            'charged': charged,
            'drained': drained,
          }),
          sourceDevice: _string(item['source_device']) ?? 'garmin',
        ),
      );
    }
  }
}

class _GarminMetricBatchBuilder {
  final List<RawHealthMetric> rows = <RawHealthMetric>[];
  final List<String> errors = <String>[];
  final Map<HealthMetricKind, int> countsByKind = <HealthMetricKind, int>{};

  void add(RawHealthMetric metric) {
    rows.add(metric);
    countsByKind.update(metric.kind, (v) => v + 1, ifAbsent: () => 1);
  }

  void addDaily({
    required String? id,
    required String? date,
    required HealthMetricKind kind,
    required double? value,
    String? unit,
    String? sourceDevice,
  }) {
    if (id == null || date == null || value == null) return;
    add(
      RawHealthMetric(
        id: id,
        capturedAt: _parseDayStart(date),
        kind: kind,
        value: value,
        unit: unit ?? kind.defaultUnit,
        sourceDevice: sourceDevice,
      ),
    );
  }
}

List<Map<String, dynamic>> _mapList(Object? value) {
  if (value is! List) return const <Map<String, dynamic>>[];
  return value
      .whereType<Map<Object?, Object?>>()
      .map(
        (entry) => entry.map((key, value) => MapEntry(key.toString(), value)),
      )
      .toList();
}

String? _string(Object? value) {
  if (value == null) return null;
  if (value is String) return value;
  return value.toString();
}

double? _number(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

int? _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

DateTime _parseDayStart(String date) {
  final parts = date.split('-').map(int.parse).toList();
  return DateTime.utc(parts[0], parts[1], parts[2]);
}

DateTime? _parseInstant(String? value) {
  if (value == null || value.isEmpty) return null;
  return DateTime.tryParse(value)?.toUtc();
}
