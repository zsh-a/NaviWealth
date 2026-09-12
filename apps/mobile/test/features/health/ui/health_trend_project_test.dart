import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/health/composition/health_trend_location.dart';
import 'package:naviwealth/features/health/data/health_series.dart';
import 'package:naviwealth/features/health/domain/health_metric.dart';
import 'package:naviwealth/features/health/domain/health_metric_kind.dart';

HealthMetric _row({
  required String id,
  required HealthMetricKind kind,
  required DateTime at,
  required double value,
  String? unit,
  String? source,
}) => HealthMetric(
  id: id,
  capturedAt: at,
  kind: kind,
  value: value,
  unit: unit ?? kind.defaultUnit,
  sourceDevice: source,
  sync: SyncMeta(
    ownerUserId: 'u',
    updatedAt: at,
    updatedByDevice: 'dev',
    hlc: Hlc(wallMillis: at.millisecondsSinceEpoch, counter: 0, nodeId: 'dev'),
    deletedAt: null,
  ),
);

void main() {
  final now = DateTime.utc(2026, 5, 27, 12);
  final window = HealthWindow(now: now, days: 7);

  group('healthTrendPath', () {
    test('encodes exact metric target', () {
      expect(
        healthTrendPath(metricKind: HealthMetricKind.hrvDaily),
        '/health/trend?metric=hrv_daily',
      );
      expect(
        healthTrendPath(metricKind: HealthMetricKind.activeEnergyDaily),
        '/health/trend?group=activity&metric=active_energy_daily',
      );
    });

    test('keeps exact metric target when changing window', () {
      expect(
        healthTrendPath(
          metricKind: HealthMetricKind.stepsDaily,
          windowDays: 90,
        ),
        '/health/trend?group=activity&metric=steps_daily&window=90',
      );
    });
  });

  test('default URL has no empty query', () {
    expect(healthTrendPath(), '/health/trend');
  });

  test('windows contain exactly 7/30/90 calendar dates including today', () {
    for (final days in [7, 30, 90]) {
      final w = HealthWindow(now: now, days: days);
      expect(w.dates.length, days);
      expect(w.contains(w.start), isTrue);
      expect(w.contains(w.end), isFalse);
      expect(w.previous.end, w.start);
    }
  });

  HealthSeries project(HealthMetricKind kind, List<HealthMetric> rows) =>
      buildHealthSeries(
        kind: kind,
        rows: rows,
        window: window,
        localize: (d) => d.toUtc(),
      );

  test('canonical daily source wins; missing dates stay gaps, not zero', () {
    final series = project(HealthMetricKind.stepsDaily, [
      _row(
        id: 'garmin:steps:1',
        kind: HealthMetricKind.stepsDaily,
        at: now,
        value: 6000,
        source: 'Garmin',
      ),
      _row(
        id: 'hk:steps:1',
        kind: HealthMetricKind.stepsDaily,
        at: now,
        value: 9000,
        source: 'HealthKit',
      ),
      _row(
        id: 'garmin:steps:2',
        kind: HealthMetricKind.stepsDaily,
        at: now.subtract(const Duration(days: 2)),
        value: 0,
      ),
    ]);
    expect(series.samples.map((s) => s.value), [0, 6000]);
    expect(series.recordedDays, 2);
    expect(series.average, 3000);
    expect(series.segments.length, 2);
    expect(series.latest!.records.single.id, 'garmin:steps:1');
  });

  test('sleep sums night and nap by wake day after source deduplication', () {
    final night = DateTime.utc(2026, 5, 26, 23);
    final series = project(HealthMetricKind.sleepSession, [
      _row(
        id: 'garmin:sleep:night',
        kind: HealthMetricKind.sleepSession,
        at: night,
        value: 7,
        unit: 'h',
      ),
      _row(
        id: 'hk:sleep:night',
        kind: HealthMetricKind.sleepSession,
        at: night,
        value: 420,
        unit: 'min',
      ),
      _row(
        id: 'garmin:sleep:nap',
        kind: HealthMetricKind.sleepSession,
        at: DateTime.utc(2026, 5, 27, 13),
        value: 1800,
      ),
    ]);
    expect(series.samples.single.day, DateTime.utc(2026, 5, 27));
    expect(series.samples.single.value, 7.5);
    expect(series.samples.single.records.length, 2);
  });

  test('session attribution is local, encoded daily dates never shift', () {
    final at = DateTime.utc(2026, 5, 26, 23);
    DateTime east(DateTime d) => d.toUtc().add(const Duration(hours: 8));
    final workout = _row(
      id: 'w',
      kind: HealthMetricKind.workoutSession,
      at: at,
      value: 1800,
    );
    final daily = _row(
      id: 'd',
      kind: HealthMetricKind.stepsDaily,
      at: DateTime.utc(2026, 5, 26),
      value: 500,
    );
    expect(healthMetricDay(workout, localize: east), DateTime.utc(2026, 5, 27));
    expect(
      healthMetricDay(
        daily,
        localize: (d) => d.subtract(const Duration(hours: 8)),
      ),
      DateTime.utc(2026, 5, 26),
    );
  });

  test(
    'manual date does not shift and body fat converts fraction to percent',
    () {
      final row = _row(
        id: 'manual:body_fat:u:2026-05-27',
        kind: HealthMetricKind.bodyFat,
        at: DateTime.utc(2026, 5, 27, 12),
        value: 0.184,
      );
      expect(
        healthMetricDay(row, localize: (d) => d.add(const Duration(hours: 14))),
        DateTime.utc(2026, 5, 27),
      );
      expect(
        project(HealthMetricKind.bodyFat, [row]).latest!.value,
        closeTo(18.4, 1e-6),
      );
    },
  );

  test('workout durations use units and sum distinct sessions', () {
    final series = project(HealthMetricKind.workoutSession, [
      _row(
        id: 'w1',
        kind: HealthMetricKind.workoutSession,
        at: now,
        value: 30,
        unit: 'min',
      ),
      _row(
        id: 'w2',
        kind: HealthMetricKind.workoutSession,
        at: now.add(const Duration(hours: 1)),
        value: 1200,
      ),
    ]);
    expect(series.samples.single.value, 50);
  });

  test('unfinished activity day is excluded from equal-period comparison', () {
    final series = project(HealthMetricKind.stepsDaily, [
      for (var i = 0; i < 14; i++)
        _row(
          id: 'steps-$i',
          kind: HealthMetricKind.stepsDaily,
          at: now.subtract(Duration(days: i)),
          value: i == 0
              ? 10
              : i < 7
              ? 200
              : 100,
        ),
    ]);
    expect(series.changePercent, 100);
    expect(series.total, 1210);
  });

  test(
    'single observation remains visible without a fabricated comparison',
    () {
      final series = project(HealthMetricKind.weight, [
        _row(id: 'weight', kind: HealthMetricKind.weight, at: now, value: 72.5),
      ]);
      expect(series.latest!.value, 72.5);
      expect(series.changePercent, isNull);
      expect(series.segments.single.length, 1);
    },
  );

  test('outside windows and invalid values never reach charts', () {
    final series = project(HealthMetricKind.hrvDaily, [
      _row(
        id: 'old',
        kind: HealthMetricKind.hrvDaily,
        at: now.subtract(const Duration(days: 15)),
        value: 30,
      ),
      _row(
        id: 'future',
        kind: HealthMetricKind.hrvDaily,
        at: now.add(const Duration(days: 1)),
        value: 30,
      ),
      _row(
        id: 'bad',
        kind: HealthMetricKind.hrvDaily,
        at: now,
        value: double.nan,
      ),
      _row(id: 'negative', kind: HealthMetricKind.hrvDaily, at: now, value: -1),
    ]);
    expect(series.samples, isEmpty);
    expect(series.previousSamples, isEmpty);
  });
}
