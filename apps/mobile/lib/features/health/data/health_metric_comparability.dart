import 'dart:convert';

import '../domain/health_metric.dart';
import '../domain/health_metric_kind.dart';
import 'health_metric_selector.dart';
import 'health_metric_source.dart';

String? healthMeasurementMethod(HealthMetric metric) {
  try {
    final payload = jsonDecode(metric.payloadJson ?? '{}');
    if (payload is Map<String, dynamic> &&
        payload['measurement_method'] is String) {
      return payload['measurement_method'] as String;
    }
  } on FormatException {
    /* Older optional payloads may be malformed. */
  }
  if (metric.kind != HealthMetricKind.hrvDaily) return null;
  // These are the methods used by this app's legacy adapters. Garmin remains
  // explicitly provider-defined rather than claiming a platform algorithm.
  return switch (sourceForHealthMetric(metric)) {
    HealthMetricSource.healthKit => 'sdnn',
    HealthMetricSource.healthConnect => 'rmssd',
    HealthMetricSource.garmin => 'garmin_nightly',
    _ => 'unspecified',
  };
}

String healthComparisonKey(HealthMetric metric) => jsonEncode([
  sourceForHealthMetric(metric).id,
  metric.sourceDevice?.trim().toLowerCase() ?? '',
  healthMeasurementMethod(metric) ?? '',
  metric.unit,
  _sourceOrigin(metric),
]);

String _sourceOrigin(HealthMetric metric) {
  try {
    final payload = jsonDecode(metric.payloadJson ?? '{}');
    if (payload is Map<String, dynamic>) {
      return payload['source_origin']?.toString() ?? '';
    }
  } on FormatException {
    /* Legacy readings have no origin metadata. */
  }
  return '';
}

/// Compare only the newest active measurement family. A device/method switch
/// starts learning a new baseline instead of borrowing incompatible history.
List<HealthMetric> comparableHealthMetrics(
  HealthMetricKind kind,
  List<HealthMetric> rows, {
  HealthMetricSource? preferredSource,
}) {
  final canonical = selectCanonicalMetricsForKind(
    kind,
    rows,
    preferredSource: preferredSource,
  );
  if (canonical.isEmpty) return const [];
  final key = healthComparisonKey(canonical.first);
  return selectCanonicalMetricsForKind(
    kind,
    rows.where((row) => healthComparisonKey(row) == key).toList(),
    preferredSource: preferredSource,
  );
}
