/// Canonical HealthOS metric selection across multiple sources.
///
/// `health_metrics` keeps source rows intact so sync remains lossless. Read
/// models call this selector to avoid double-counting the same logical daily
/// metric when Garmin and HealthKit / Health Connect both report it.
library;

import '../domain/health_metric.dart';
import '../domain/health_metric_kind.dart';
import 'health_metric_source.dart';

Map<HealthMetricKind, List<HealthMetric>> selectCanonicalHealthMetrics(
  Map<HealthMetricKind, List<HealthMetric>> raw,
) {
  return <HealthMetricKind, List<HealthMetric>>{
    for (final entry in raw.entries)
      entry.key: selectCanonicalMetricsForKind(entry.key, entry.value),
  };
}

List<HealthMetric> selectCanonicalMetricsForKind(
  HealthMetricKind kind,
  List<HealthMetric> rows,
) {
  if (rows.length < 2) return rows;

  final byBucket = <String, HealthMetric>{};
  for (final row in rows) {
    final key = _bucketKey(kind, row);
    final current = byBucket[key];
    if (current == null || _isBetter(row, current)) {
      byBucket[key] = row;
    }
  }

  final selected = byBucket.values.toList()
    ..sort((a, b) => b.capturedAt.compareTo(a.capturedAt));
  return List<HealthMetric>.unmodifiable(selected);
}

bool _isBetter(HealthMetric candidate, HealthMetric incumbent) {
  final cSource = sourceForHealthMetric(candidate);
  final iSource = sourceForHealthMetric(incumbent);
  final sourceDelta = cSource.priority.compareTo(iSource.priority);
  if (sourceDelta != 0) return sourceDelta > 0;

  final updateDelta = candidate.sync.updatedAt.compareTo(
    incumbent.sync.updatedAt,
  );
  if (updateDelta != 0) return updateDelta > 0;

  return candidate.capturedAt.isAfter(incumbent.capturedAt);
}

String _bucketKey(HealthMetricKind kind, HealthMetric row) {
  if (_dailyKinds.contains(kind) || kind == HealthMetricKind.sleepSession) {
    return _utcDayKey(row.capturedAt);
  }
  if (kind == HealthMetricKind.workoutSession) {
    final t = row.capturedAt.toUtc();
    final minute = t.minute.toString().padLeft(2, '0');
    return '${_utcDayKey(t)}T${t.hour.toString().padLeft(2, '0')}:$minute';
  }
  return row.id;
}

String _utcDayKey(DateTime t) {
  final utc = t.toUtc();
  final y = utc.year.toString().padLeft(4, '0');
  final m = utc.month.toString().padLeft(2, '0');
  final d = utc.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

const Set<HealthMetricKind> _dailyKinds = <HealthMetricKind>{
  HealthMetricKind.hrvDaily,
  HealthMetricKind.stepsDaily,
  HealthMetricKind.rhrDaily,
  HealthMetricKind.activeEnergyDaily,
  HealthMetricKind.vo2Max,
  HealthMetricKind.distanceWalkingRunningDaily,
  HealthMetricKind.heartRateDaily,
  HealthMetricKind.totalEnergyDaily,
  HealthMetricKind.floorsClimbedDaily,
  HealthMetricKind.respiratoryRateDaily,
  HealthMetricKind.stressDaily,
  HealthMetricKind.bodyBatteryDaily,
  HealthMetricKind.trainingLoadDaily,
  HealthMetricKind.trainingEffectDaily,
  HealthMetricKind.spo2Daily,
};
