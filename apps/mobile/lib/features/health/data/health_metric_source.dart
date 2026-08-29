/// Source identity helpers for HealthOS metrics.
///
/// Source identity lives in the `health_metrics.source_id` column
/// (schema v79). Rows written before that column — or synced from older
/// devices — have it NULL and still resolve through the stable row id
/// prefixes written by each adapter (`garmin:`, `hk:`, `hc:`,
/// `manual:`) and the legacy `sourceDevice` text.
library;

import 'package:naviwealth/core/persistence/app_database.dart';

import '../domain/health_metric.dart';

enum HealthMetricSource { garmin, healthKit, healthConnect, manual, unknown }

extension HealthMetricSourceX on HealthMetricSource {
  String get id => switch (this) {
    HealthMetricSource.garmin => 'garmin',
    HealthMetricSource.healthKit => 'healthkit',
    HealthMetricSource.healthConnect => 'health_connect',
    HealthMetricSource.manual => 'manual',
    HealthMetricSource.unknown => 'unknown',
  };

  String get label => switch (this) {
    HealthMetricSource.garmin => 'Garmin',
    HealthMetricSource.healthKit => 'HealthKit',
    HealthMetricSource.healthConnect => 'Health Connect',
    HealthMetricSource.manual => 'Manual',
    HealthMetricSource.unknown => 'Unknown',
  };

  /// Higher priority wins when multiple sources report the same logical metric
  /// for the same day/session. Garmin wins for recovery metrics because it is
  /// the only source that also supplies stress/body battery/training context.
  int get priority => switch (this) {
    HealthMetricSource.garmin => 40,
    HealthMetricSource.healthKit => 30,
    HealthMetricSource.healthConnect => 20,
    HealthMetricSource.manual => 10,
    HealthMetricSource.unknown => 0,
  };
}

/// Resolves a persisted `source_id` value back to its source. Returns
/// `null` for NULL, empty, or unrecognized values so callers can fall
/// back to the id-prefix / device-name derivation.
HealthMetricSource? healthMetricSourceFromId(String? persistedSourceId) {
  final value = persistedSourceId?.toLowerCase().trim();
  if (value == null || value.isEmpty) return null;
  for (final source in HealthMetricSource.values) {
    if (source.id == value) return source;
  }
  return null;
}

/// Derives the source from identity that predates the `source_id`
/// column: adapter row-id prefixes first, then the legacy free-text
/// device attribution.
HealthMetricSource legacyHealthMetricSource({
  required String rowId,
  String? sourceDevice,
}) {
  final id = rowId.toLowerCase();
  if (id.startsWith('garmin:')) return HealthMetricSource.garmin;
  if (id.startsWith('hk:')) return HealthMetricSource.healthKit;
  if (id.startsWith('hc:')) return HealthMetricSource.healthConnect;
  if (id.startsWith('manual:')) return HealthMetricSource.manual;

  final device = sourceDevice?.toLowerCase().trim();
  if (device == null || device.isEmpty) return HealthMetricSource.unknown;
  if (device.contains('garmin')) return HealthMetricSource.garmin;
  if (device.contains('health connect')) {
    return HealthMetricSource.healthConnect;
  }
  if (device.contains('apple') || device.contains('watch')) {
    return HealthMetricSource.healthKit;
  }
  if (device == 'manual') return HealthMetricSource.manual;
  return HealthMetricSource.unknown;
}

HealthMetricSource sourceForHealthMetric(HealthMetric metric) =>
    legacyHealthMetricSource(rowId: metric.id, sourceDevice: metric.sourceDevice);

/// Resolves the source of a persisted metric row: the `source_id`
/// column wins, and legacy rows fall back to the prefix / device-name
/// derivation.
HealthMetricSource sourceForHealthMetricRow(HealthMetricRow row) =>
    healthMetricSourceFromId(row.sourceId) ??
    legacyHealthMetricSource(rowId: row.id, sourceDevice: row.sourceDevice);
