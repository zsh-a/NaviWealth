import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/health/data/health_metric_selector.dart';
import 'package:naviwealth/features/health/data/health_metric_source.dart';
import 'package:naviwealth/features/health/domain/health_metric.dart';
import 'package:naviwealth/features/health/domain/health_metric_kind.dart';

const _userId = 'u-test';
const _deviceId = 'dev-test';

HealthMetric _metric({
  required String id,
  required DateTime capturedAt,
  required double value,
  HealthMetricKind kind = HealthMetricKind.hrvDaily,
  int updatedOffset = 0,
}) {
  return HealthMetric(
    id: id,
    capturedAt: capturedAt,
    kind: kind,
    value: value,
    unit: kind.defaultUnit,
    sync: SyncMeta(
      ownerUserId: _userId,
      updatedAt: DateTime.utc(
        2026,
        6,
        14,
        8,
      ).add(Duration(minutes: updatedOffset)),
      updatedByDevice: _deviceId,
      hlc: Hlc(
        wallMillis: 1_765_000_000_000 + updatedOffset,
        counter: 0,
        nodeId: _deviceId,
      ),
    ),
  );
}

void main() {
  test('source resolver derives source from stable id prefixes', () {
    expect(
      sourceForHealthMetric(
        _metric(
          id: 'garmin:hrv:2026-06-14',
          capturedAt: DateTime.utc(2026, 6, 14),
          value: 70,
        ),
      ),
      HealthMetricSource.garmin,
    );
    expect(
      sourceForHealthMetric(
        _metric(
          id: 'hk:hrv:2026-06-14',
          capturedAt: DateTime.utc(2026, 6, 14),
          value: 60,
        ),
      ),
      HealthMetricSource.healthKit,
    );
    expect(
      sourceForHealthMetric(
        _metric(
          id: 'hc:hrv:2026-06-14',
          capturedAt: DateTime.utc(2026, 6, 14),
          value: 50,
        ),
      ),
      HealthMetricSource.healthConnect,
    );
  });

  test('canonical selector keeps one preferred source per daily bucket', () {
    final rows = <HealthMetric>[
      _metric(
        id: 'hk:hrv:2026-06-14',
        capturedAt: DateTime.utc(2026, 6, 14),
        value: 55,
        updatedOffset: 10,
      ),
      _metric(
        id: 'garmin:hrv:2026-06-14',
        capturedAt: DateTime.utc(2026, 6, 14),
        value: 72,
      ),
      _metric(
        id: 'hk:hrv:2026-06-13',
        capturedAt: DateTime.utc(2026, 6, 13),
        value: 58,
      ),
    ];

    final selected = selectCanonicalMetricsForKind(
      HealthMetricKind.hrvDaily,
      rows,
    );

    expect(selected.map((m) => m.id), [
      'garmin:hrv:2026-06-14',
      'hk:hrv:2026-06-13',
    ]);
  });

  test('sleep selector preserves independent sessions on the same day', () {
    final rows = <HealthMetric>[
      _metric(
        id: 'hk:sleep:night',
        kind: HealthMetricKind.sleepSession,
        capturedAt: DateTime.utc(2026, 6, 14),
        value: 8 * 3600,
      ),
      _metric(
        id: 'hk:sleep:nap',
        kind: HealthMetricKind.sleepSession,
        capturedAt: DateTime.utc(2026, 6, 14, 13),
        value: 45 * 60,
      ),
    ];

    final selected = selectCanonicalMetricsForKind(
      HealthMetricKind.sleepSession,
      rows,
    );

    expect(selected.map((metric) => metric.id), [
      'hk:sleep:nap',
      'hk:sleep:night',
    ]);
  });

  test('sleep selector deduplicates highly overlapping source sessions', () {
    final rows = <HealthMetric>[
      _metric(
        id: 'hk:sleep:night',
        kind: HealthMetricKind.sleepSession,
        capturedAt: DateTime.utc(2026, 6, 14),
        value: 8 * 3600,
      ),
      _metric(
        id: 'garmin:sleep:night',
        kind: HealthMetricKind.sleepSession,
        capturedAt: DateTime.utc(2026, 6, 14, 0, 10),
        value: 7.8 * 3600,
      ),
    ];

    final selected = selectCanonicalMetricsForKind(
      HealthMetricKind.sleepSession,
      rows,
    );

    expect(selected.map((metric) => metric.id), ['garmin:sleep:night']);
  });
}
