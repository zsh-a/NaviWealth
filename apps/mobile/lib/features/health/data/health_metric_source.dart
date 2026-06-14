/// Source identity helpers for HealthOS metrics.
///
/// The Drift table does not have a dedicated `source_id` column yet. Until that
/// schema lands, source identity is derived from stable row id prefixes written
/// by each adapter (`garmin:`, `hk:`, `hc:`) and the legacy `sourceDevice`.
library;

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

HealthMetricSource sourceForHealthMetric(HealthMetric metric) {
  final id = metric.id.toLowerCase();
  if (id.startsWith('garmin:')) return HealthMetricSource.garmin;
  if (id.startsWith('hk:')) return HealthMetricSource.healthKit;
  if (id.startsWith('hc:')) return HealthMetricSource.healthConnect;
  if (id.startsWith('manual:')) return HealthMetricSource.manual;

  final device = metric.sourceDevice?.toLowerCase().trim();
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
