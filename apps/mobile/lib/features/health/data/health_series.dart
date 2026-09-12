/// Calendar-based, source-deduplicated read models shared by Health surfaces.
library;

import '../domain/health_metric.dart';
import '../domain/health_metric_kind.dart';
import 'health_metric_selector.dart';

/// UTC is only a date container here, not an instant to display in local time.
DateTime healthDay(DateTime date) =>
    DateTime.utc(date.year, date.month, date.day);

class HealthWindow {
  HealthWindow({required DateTime now, required int days})
    : today = healthDay(now),
      days = days.clamp(1, 90);

  final DateTime today;
  final int days;
  DateTime get start => today.subtract(Duration(days: days - 1));
  DateTime get end => today.add(const Duration(days: 1));
  HealthWindow get previous =>
      HealthWindow(now: start.subtract(const Duration(days: 1)), days: days);
  bool contains(DateTime day) => !day.isBefore(start) && day.isBefore(end);
  Iterable<DateTime> get dates sync* {
    for (var i = 0; i < days; i++) {
      yield start.add(Duration(days: i));
    }
  }
}

double healthDurationSeconds(HealthMetric row) => switch (row.unit) {
  'h' => row.value * 3600,
  'min' => row.value * 60,
  _ => row.value,
};

/// Daily sources already store a calendar date encoded as UTC midnight. Never
/// apply a second timezone shift to it. Sessions use local start/wake dates.
DateTime healthMetricDay(
  HealthMetric row, {
  DateTime Function(DateTime)? localize,
}) {
  final local = localize ?? (date) => date.toLocal();
  return switch (row.kind) {
    HealthMetricKind.sleepSession => healthDay(
      local(
        row.capturedAt.add(
          Duration(seconds: healthDurationSeconds(row).round()),
        ),
      ),
    ),
    HealthMetricKind.workoutSession => healthDay(local(row.capturedAt)),
    HealthMetricKind.weight || HealthMetricKind.bodyFat => healthDay(
      row.id.startsWith('manual:')
          ? row.capturedAt.toUtc()
          : local(row.capturedAt),
    ),
    _ => healthDay(row.capturedAt.toUtc()),
  };
}

double healthDisplayValue(HealthMetric row) => switch (row.kind) {
  HealthMetricKind.sleepSession => healthDurationSeconds(row) / 3600,
  HealthMetricKind.workoutSession => healthDurationSeconds(row) / 60,
  HealthMetricKind.bodyFat =>
    row.unit == 'fraction' ? row.value * 100 : row.value,
  HealthMetricKind.distanceWalkingRunningDaily => row.value / 1000,
  _ => row.value,
};

extension HealthSeriesKind on HealthMetricKind {
  bool get isCumulative => switch (this) {
    HealthMetricKind.stepsDaily ||
    HealthMetricKind.activeEnergyDaily ||
    HealthMetricKind.totalEnergyDaily ||
    HealthMetricKind.distanceWalkingRunningDaily ||
    HealthMetricKind.floorsClimbedDaily ||
    HealthMetricKind.workoutSession => true,
    _ => false,
  };
  bool get isMeasurement =>
      this == HealthMetricKind.weight || this == HealthMetricKind.bodyFat;
}

class HealthDaySample {
  const HealthDaySample({
    required this.day,
    required this.value,
    required this.records,
  });
  final DateTime day;
  final double value;

  /// Canonical source records, newest first. Never fabricated zero rows.
  final List<HealthMetric> records;
}

class HealthSeries {
  const HealthSeries({
    required this.kind,
    required this.window,
    required this.samples,
    required this.previousSamples,
  });
  final HealthMetricKind kind;
  final HealthWindow window;
  final List<HealthDaySample> samples;
  final List<HealthDaySample> previousSamples;

  HealthDaySample? get latest => samples.lastOrNull;
  int get recordedDays => samples.length;
  double get total => samples.fold(0, (sum, sample) => sum + sample.value);
  double? get average => samples.isEmpty ? null : total / samples.length;
  double? get summary =>
      kind.isMeasurement || kind == HealthMetricKind.trainingEffectDaily
      ? latest?.value
      : average;

  /// Compare recorded days in equal-length calendar windows. An unfinished
  /// activity day is not compared against a full day. Expose coverage in UI.
  double? get changePercent {
    if (kind == HealthMetricKind.trainingEffectDaily) return null;
    final recent = samples
        .where((s) => !kind.isCumulative || s.day != window.today)
        .toList();
    final prior = previousSamples
        .where((s) => !kind.isCumulative || s.day != window.previous.today)
        .toList();
    if (recent.length < 2 || prior.length < 2) return null;
    final before =
        prior.fold<double>(0, (sum, s) => sum + s.value) / prior.length;
    final after =
        recent.fold<double>(0, (sum, s) => sum + s.value) / recent.length;
    if (before == 0) return null;
    return (after - before) / before * 100;
  }

  /// Keep separate segments across unobserved dates; never invent continuity.
  List<List<HealthDaySample>> get segments {
    final result = <List<HealthDaySample>>[];
    for (final sample in samples) {
      if (result.isEmpty ||
          sample.day.difference(result.last.last.day).inDays > 1) {
        result.add([]);
      }
      result.last.add(sample);
    }
    return result;
  }
}

HealthSeries buildHealthSeries({
  required HealthMetricKind kind,
  required List<HealthMetric> rows,
  required HealthWindow window,
  DateTime Function(DateTime)? localize,
}) {
  final canonical = selectCanonicalMetricsForKind(
    kind,
    rows
        .where(
          (row) =>
              row.kind == kind &&
              kind != HealthMetricKind.unknown &&
              row.value.isFinite &&
              row.value >= 0 &&
              row.sync.deletedAt == null,
        )
        .toList(),
  );
  final buckets = <DateTime, List<HealthMetric>>{};
  for (final row in canonical) {
    if (!row.value.isFinite || row.value < 0) continue;
    final day = healthMetricDay(row, localize: localize);
    if (!window.contains(day) && !window.previous.contains(day)) continue;
    buckets.putIfAbsent(day, () => []).add(row);
  }
  final samples = <HealthDaySample>[];
  for (final entry in buckets.entries) {
    final records = entry.value
      ..sort((a, b) => b.capturedAt.compareTo(a.capturedAt));
    final value =
        kind == HealthMetricKind.sleepSession ||
            kind == HealthMetricKind.workoutSession
        ? records.fold<double>(0, (sum, row) => sum + healthDisplayValue(row))
        : healthDisplayValue(records.first);
    samples.add(
      HealthDaySample(
        day: entry.key,
        value: value,
        records: List.unmodifiable(records),
      ),
    );
  }
  samples.sort((a, b) => a.day.compareTo(b.day));
  return HealthSeries(
    kind: kind,
    window: window,
    samples: List.unmodifiable(samples.where((s) => window.contains(s.day))),
    previousSamples: List.unmodifiable(
      samples.where((s) => window.previous.contains(s.day)),
    ),
  );
}
