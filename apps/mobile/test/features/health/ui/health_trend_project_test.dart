// D-2.7 Trend projection tests.
//
// `healthTrendProject` shapes rows → ChartPoints. Test the projection
// in isolation so the chart widget doesn't drag fl_chart paint code
// into a unit-test harness.

import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/health/domain/health_metric.dart';
import 'package:naviwealth/features/health/domain/health_metric_kind.dart';
import 'package:naviwealth/features/health/ui/health_trend_page.dart';

HealthMetric _row({
  required String id,
  required HealthMetricKind kind,
  required DateTime at,
  required double value,
  String? unit,
}) => HealthMetric(
  id: id,
  capturedAt: at,
  kind: kind,
  value: value,
  unit: unit ?? kind.defaultUnit,
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
  final cutoff = now.subtract(const Duration(days: 30));

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

  group('healthTrendProject', () {
    test('hrv rows → ascending points, values pass through', () {
      final pts = healthTrendProject(
        rows: [
          _row(
            id: 'h2',
            kind: HealthMetricKind.hrvDaily,
            at: now.subtract(const Duration(days: 1)),
            value: 52,
          ),
          _row(
            id: 'h1',
            kind: HealthMetricKind.hrvDaily,
            at: now.subtract(const Duration(days: 3)),
            value: 48,
          ),
        ],
        kind: HealthMetricKind.hrvDaily,
        cutoff: cutoff,
      );
      expect(pts, hasLength(2));
      expect(pts.first.y, 48);
      expect(pts.last.y, 52);
      expect(pts.first.x, lessThan(pts.last.x));
    });

    test('sleep rows → hours conversion', () {
      final pts = healthTrendProject(
        rows: [
          _row(
            id: 's1',
            kind: HealthMetricKind.sleepSession,
            at: now.subtract(const Duration(days: 1)),
            value: 7 * 3600.0,
          ),
        ],
        kind: HealthMetricKind.sleepSession,
        cutoff: cutoff,
      );
      expect(pts.single.y, 7.0);
    });

    test('workout rows aggregate per UTC day, value = minutes', () {
      final day = DateTime.utc(2026, 5, 25);
      final pts = healthTrendProject(
        rows: [
          // Two sessions same day = 30min + 20min = 50min
          _row(
            id: 'w1',
            kind: HealthMetricKind.workoutSession,
            at: day.add(const Duration(hours: 7)),
            value: 30 * 60,
          ),
          _row(
            id: 'w2',
            kind: HealthMetricKind.workoutSession,
            at: day.add(const Duration(hours: 18)),
            value: 20 * 60,
          ),
        ],
        kind: HealthMetricKind.workoutSession,
        cutoff: cutoff,
      );
      expect(pts, hasLength(1));
      expect(pts.single.y, closeTo(50.0, 1e-6));
    });

    test('rows before cutoff are dropped', () {
      final pts = healthTrendProject(
        rows: [
          _row(
            id: 'old',
            kind: HealthMetricKind.hrvDaily,
            at: now.subtract(const Duration(days: 60)), // before cutoff
            value: 70,
          ),
          _row(
            id: 'new',
            kind: HealthMetricKind.hrvDaily,
            at: now.subtract(const Duration(days: 2)),
            value: 50,
          ),
        ],
        kind: HealthMetricKind.hrvDaily,
        cutoff: cutoff,
      );
      expect(pts, hasLength(1));
      expect(pts.single.y, 50);
    });

    test('unknown kind → empty list', () {
      final pts = healthTrendProject(
        rows: [
          _row(
            id: 'x',
            kind: HealthMetricKind.unknown,
            at: now,
            value: 1,
            unit: 'foo',
          ),
        ],
        kind: HealthMetricKind.unknown,
        cutoff: cutoff,
      );
      expect(pts, isEmpty);
    });
  });
}
