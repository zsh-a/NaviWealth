/// One explainable recovery heuristic shared by UI, tools, and analyzers.
library;

import '../domain/health_metric.dart';
import '../domain/health_metric_kind.dart';
import 'health_metric_comparability.dart';
import 'health_metric_source.dart';
import 'health_series.dart';

class RecoveryResult {
  const RecoveryResult({
    required this.score,
    required this.verdict,
    required this.inputs,
    required this.confidence,
    required this.coverage,
    required this.freshnessHours,
    required this.components,
  });
  final int? score;
  final String verdict;
  final Map<String, Object?> inputs;
  final String confidence;
  final double coverage;

  /// Age of the oldest contributing input's latest observation.
  final double? freshnessHours;

  /// Includes learning/unavailable inputs as well as scored components.
  final List<Map<String, Object?>> components;
  bool get hasScore => score != null;
  Map<String, Object?> toJson() => {
    'score': score,
    'verdict': verdict,
    'inputs': inputs,
    'confidence': confidence,
    'coverage': coverage,
    'freshness_hours': freshnessHours,
    'components': components,
  };
}

class RecoveryScorer {
  const RecoveryScorer();
  static const minimumBaselineDays = 5;

  RecoveryResult score({
    required List<HealthMetric> hrv,
    required List<HealthMetric> sleep,
    required List<HealthMetric> rhr,
    List<HealthMetric> vo2Max = const [],
    List<HealthMetric> bodyBattery = const [],
    List<HealthMetric> stress = const [],
    Map<HealthMetricKind, HealthMetricSource> preferredSources = const {},
    double? sleepGoalHours,
    DateTime? now,
  }) {
    final t = now ?? DateTime.now();
    final today = healthDay(t);
    final recentFrom = today.subtract(const Duration(days: 6));
    final baselineFrom = today.subtract(const Duration(days: 27));
    final goal =
        sleepGoalHours != null &&
            sleepGoalHours.isFinite &&
            sleepGoalHours >= 4 &&
            sleepGoalHours <= 12
        ? sleepGoalHours
        : null;
    final components = <Map<String, Object?>>[];
    final scores = <double>[];
    final ages = <double>[];
    final sampleCounts = <int>[];
    final inputs = <String, Object?>{};

    for (final (key, kind, raw, inputKey, inverse) in [
      ('hrv', HealthMetricKind.hrvDaily, hrv, 'latest_hrv_ms', false),
      ('sleep', HealthMetricKind.sleepSession, sleep, 'avg_sleep_hours', false),
      ('rhr', HealthMetricKind.rhrDaily, rhr, 'latest_rhr_bpm', true),
      ('vo2_max', HealthMetricKind.vo2Max, vo2Max, 'latest_vo2_max', false),
      (
        'body_battery',
        HealthMetricKind.bodyBatteryDaily,
        bodyBattery,
        'latest_body_battery',
        false,
      ),
      ('stress', HealthMetricKind.stressDaily, stress, 'latest_stress', true),
    ]) {
      final rows = comparableHealthMetrics(
        kind,
        raw
            .where(
              (row) =>
                  row.kind == kind &&
                  row.sync.deletedAt == null &&
                  row.value.isFinite &&
                  row.value >= 0 &&
                  (kind == HealthMetricKind.sleepSession
                      ? !row.capturedAt
                            .add(
                              Duration(
                                seconds: healthDurationSeconds(row).round(),
                              ),
                            )
                            .isAfter(t)
                      : !healthMetricDay(row).isAfter(today)) &&
                  (kind == HealthMetricKind.sleepSession
                      ? const ['s', 'min', 'h'].contains(row.unit)
                      : row.unit == kind.defaultUnit),
            )
            .toList(),
        preferredSource: preferredSources[kind],
      );
      final recent = _days(
        rows,
        recentFrom,
        today.add(const Duration(days: 1)),
      );
      final baseline = _days(rows, baselineFrom, recentFrom);
      final recentValue = _average(recent);
      final baselineValue = _average(baseline);
      inputs[inputKey] = recentValue == null ? null : _round(recentValue);
      if (rows.isEmpty) continue;

      final recentRows = rows
          .where((row) => recent.containsKey(healthMetricDay(row)))
          .toList();
      final latest = recentRows.isEmpty
          ? null
          : recentRows
                .map((row) => row.capturedAt)
                .reduce((a, b) => a.isAfter(b) ? a : b);
      final age = latest == null ? null : t.difference(latest).inMinutes / 60;
      final useGoal = kind == HealthMetricKind.sleepSession && goal != null;
      final reference = useGoal ? goal : baselineValue;
      final eligible =
          recentValue != null &&
          reference != null &&
          reference > 0 &&
          (useGoal || baseline.length >= minimumBaselineDays);
      final status = recentValue == null
          ? 'missing_recent'
          : eligible
          ? 'ready'
          : 'learning';
      double? componentScore;
      if (eligible) {
        componentScore = kind == HealthMetricKind.sleepSession
            ? _clamp((useGoal ? 75 : 50) + (recentValue - reference) * 20)
            : _clamp(
                50 +
                    (inverse ? -1 : 1) *
                        (recentValue - reference) /
                        reference *
                        125,
              );
        scores.add(componentScore);
        if (age != null) ages.add(age);
        sampleCounts.add(recent.length);
      }
      final source = rows.first;
      components.add({
        'metric': key,
        'status': status,
        'included': eligible,
        'score': componentScore == null ? null : _round(componentScore),
        'recent_samples': recent.length,
        'baseline_samples': baseline.length,
        'baseline_days_required': minimumBaselineDays,
        'recent_value': recentValue == null ? null : _round(recentValue),
        'baseline_value': baselineValue == null ? null : _round(baselineValue),
        'reference_value': reference == null ? null : _round(reference),
        'reference_basis': useGoal ? 'user_goal' : 'personal_baseline',
        'delta_pct':
            recentValue == null || baselineValue == null || baselineValue == 0
            ? null
            : _round((recentValue - baselineValue) / baselineValue * 100),
        'freshness_hours': age == null ? null : _round(age),
        'source_id': sourceForHealthMetric(source).id,
        'source_device': source.sourceDevice,
        'measurement_method': healthMeasurementMethod(source),
        'weight': eligible ? 1 : 0,
      });
    }

    final freshness = ages.isEmpty
        ? null
        : ages.reduce((a, b) => a > b ? a : b);
    final coverage = scores.length / 6;
    final score = scores.isEmpty
        ? null
        : (scores.reduce((a, b) => a + b) / scores.length).round();
    final confidence = score == null
        ? 'insufficient'
        : coverage >= 0.66 &&
              freshness != null &&
              freshness <= 36 &&
              sampleCounts.every((n) => n >= 3)
        ? 'high'
        : coverage >= 0.33 &&
              freshness != null &&
              freshness <= 72 &&
              sampleCounts.every((n) => n >= 2)
        ? 'medium'
        : 'low';
    return RecoveryResult(
      score: score,
      verdict: score == null
          ? 'insufficient_data'
          : score < 40
          ? 'strained'
          : score < 70
          ? 'balanced'
          : 'rested',
      inputs: inputs,
      confidence: confidence,
      coverage: _round(coverage),
      freshnessHours: freshness == null ? null : _round(freshness),
      components: List.unmodifiable(components),
    );
  }

  /// Canonical records contribute at most one sample per observed day. Sleep
  /// sessions (including naps) sum by local wake date, matching trend semantics.
  Map<DateTime, double> _days(
    List<HealthMetric> rows,
    DateTime from,
    DateTime to,
  ) {
    final result = <DateTime, double>{};
    for (final row in rows) {
      final day = healthMetricDay(row);
      if (day.isBefore(from) || !day.isBefore(to)) continue;
      final value = healthDisplayValue(row);
      if (row.kind == HealthMetricKind.sleepSession) {
        result[day] = (result[day] ?? 0) + value;
      } else {
        result.putIfAbsent(day, () => value);
      }
    }
    return result;
  }

  static double? _average(Map<DateTime, double> days) =>
      days.isEmpty ? null : days.values.reduce((a, b) => a + b) / days.length;
  static double _clamp(double value) => value.clamp(0, 100).toDouble();
  static double _round(double value) => (value * 100).round() / 100;
}
