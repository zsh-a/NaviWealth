import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/health/ai_tools/get_activity_summary_tool.dart';
import 'package:naviwealth/features/health/domain/health_metric.dart';
import 'package:naviwealth/features/health/domain/health_metric_kind.dart';

HealthMetric _metric({
  required String id,
  required HealthMetricKind kind,
  required DateTime day,
  required double value,
  required String unit,
}) => HealthMetric(
  id: id,
  capturedAt: day,
  kind: kind,
  value: value,
  unit: unit,
  sync: SyncMeta(
    ownerUserId: 'u',
    updatedAt: day,
    updatedByDevice: 'dev',
    hlc: Hlc(
      wallMillis: day.millisecondsSinceEpoch,
      counter: 0,
      nodeId: 'dev',
    ),
    deletedAt: null,
  ),
);

void main() {
  final now = DateTime.utc(2026, 5, 27, 12);

  group('GetActivitySummaryTool.shape', () {
    test('empty rows → note + zero summary', () {
      final out = GetActivitySummaryTool.shape(
        steps: const <HealthMetric>[],
        energy: const <HealthMetric>[],
        daysBack: 7,
        now: now,
      );
      expect(out['days'], isEmpty);
      final summary = out['summary'] as Map<String, Object?>;
      expect(summary['total_steps'], 0);
      expect(summary['average_steps'], isNull);
      expect(summary['total_active_kcal'], 0);
      expect(summary['average_active_kcal'], isNull);
      expect(out['note'], isNotNull);
    });

    test('joins steps + active_kcal by date, ordered ascending', () {
      final d1 = DateTime.utc(2026, 5, 25);
      final d2 = DateTime.utc(2026, 5, 26);
      final steps = [
        _metric(
          id: 's1',
          kind: HealthMetricKind.stepsDaily,
          day: d1,
          value: 10000,
          unit: 'count',
        ),
        _metric(
          id: 's2',
          kind: HealthMetricKind.stepsDaily,
          day: d2,
          value: 8500,
          unit: 'count',
        ),
      ];
      final energy = [
        _metric(
          id: 'k1',
          kind: HealthMetricKind.activeEnergyDaily,
          day: d1,
          value: 420.5,
          unit: 'kcal',
        ),
        _metric(
          id: 'k2',
          kind: HealthMetricKind.activeEnergyDaily,
          day: d2,
          value: 360.0,
          unit: 'kcal',
        ),
      ];
      final out = GetActivitySummaryTool.shape(
        steps: steps,
        energy: energy,
        daysBack: 7,
        now: now,
      );
      final days = out['days'] as List;
      expect(days, hasLength(2));
      expect((days.first as Map)['date'], '2026-05-25');
      expect((days.first as Map)['steps'], 10000);
      expect((days.first as Map)['active_kcal'], 420.5);
      expect((days.last as Map)['date'], '2026-05-26');
      final summary = out['summary'] as Map<String, Object?>;
      expect(summary['total_steps'], 18500);
      expect(summary['average_steps'], 9250);
      expect(summary['total_active_kcal'], 780.5);
      expect(summary['average_active_kcal'], 390.25);
    });

    test('asymmetric data: steps present, energy missing for a day', () {
      final d1 = DateTime.utc(2026, 5, 25);
      final d2 = DateTime.utc(2026, 5, 26);
      final out = GetActivitySummaryTool.shape(
        steps: [
          _metric(
            id: 's1',
            kind: HealthMetricKind.stepsDaily,
            day: d1,
            value: 10000,
            unit: 'count',
          ),
        ],
        energy: [
          _metric(
            id: 'k2',
            kind: HealthMetricKind.activeEnergyDaily,
            day: d2,
            value: 300,
            unit: 'kcal',
          ),
        ],
        daysBack: 7,
        now: now,
      );
      final days = out['days'] as List;
      expect(days, hasLength(2));
      final first = days.firstWhere((d) => (d as Map)['date'] == '2026-05-25')
          as Map;
      expect(first['steps'], 10000);
      expect(first['active_kcal'], isNull);
      final second = days.firstWhere((d) => (d as Map)['date'] == '2026-05-26')
          as Map;
      expect(second['steps'], isNull);
      expect(second['active_kcal'], 300);
      final summary = out['summary'] as Map<String, Object?>;
      expect(summary['step_day_count'], 1);
      expect(summary['kcal_day_count'], 1);
    });

    test('multiple readings on the same day pick the latest by capturedAt',
        () {
      final base = DateTime.utc(2026, 5, 25, 8);
      final laterSameDay = DateTime.utc(2026, 5, 25, 23, 59);
      final out = GetActivitySummaryTool.shape(
        steps: [
          _metric(
            id: 'early',
            kind: HealthMetricKind.stepsDaily,
            day: base,
            value: 5000,
            unit: 'count',
          ),
          _metric(
            id: 'late',
            kind: HealthMetricKind.stepsDaily,
            day: laterSameDay,
            value: 9500,
            unit: 'count',
          ),
        ],
        energy: const <HealthMetric>[],
        daysBack: 7,
        now: now,
      );
      final days = out['days'] as List;
      expect(days, hasLength(1));
      expect((days.single as Map)['steps'], 9500);
    });

    test(
      'workouts aggregate per day (count / minutes / distance from payload)',
      () {
        final d1 = DateTime.utc(2026, 5, 25);
        final d2 = DateTime.utc(2026, 5, 26);
        final workouts = [
          // Two sessions on d1: 30min run + 20min ride
          HealthMetric(
            id: 'w1',
            capturedAt: d1.add(const Duration(hours: 7)),
            kind: HealthMetricKind.workoutSession,
            value: 30 * 60,
            unit: 's',
            payloadJson:
                '{"activity_type":"running","total_distance_meters":5000,"total_energy_kcal":250}',
            sync: SyncMeta(
              ownerUserId: 'u',
              updatedAt: d1,
              updatedByDevice: 'dev',
              hlc: Hlc(
                wallMillis: d1.millisecondsSinceEpoch,
                counter: 0,
                nodeId: 'dev',
              ),
              deletedAt: null,
            ),
          ),
          HealthMetric(
            id: 'w2',
            capturedAt: d1.add(const Duration(hours: 18)),
            kind: HealthMetricKind.workoutSession,
            value: 20 * 60,
            unit: 's',
            payloadJson: '{"activity_type":"cycling","total_distance_meters":8000}',
            sync: SyncMeta(
              ownerUserId: 'u',
              updatedAt: d1,
              updatedByDevice: 'dev',
              hlc: Hlc(
                wallMillis: d1.millisecondsSinceEpoch + 1,
                counter: 0,
                nodeId: 'dev',
              ),
              deletedAt: null,
            ),
          ),
          // One session on d2 with no distance
          HealthMetric(
            id: 'w3',
            capturedAt: d2.add(const Duration(hours: 12)),
            kind: HealthMetricKind.workoutSession,
            value: 60 * 60,
            unit: 's',
            payloadJson: '{"activity_type":"strength_training"}',
            sync: SyncMeta(
              ownerUserId: 'u',
              updatedAt: d2,
              updatedByDevice: 'dev',
              hlc: Hlc(
                wallMillis: d2.millisecondsSinceEpoch,
                counter: 0,
                nodeId: 'dev',
              ),
              deletedAt: null,
            ),
          ),
        ];
        final out = GetActivitySummaryTool.shape(
          steps: const <HealthMetric>[],
          energy: const <HealthMetric>[],
          workouts: workouts,
          daysBack: 7,
          now: now,
        );
        final days = out['days'] as List;
        expect(days, hasLength(2));
        final dayOne = days.firstWhere(
          (d) => (d as Map)['date'] == '2026-05-25',
        ) as Map;
        expect(dayOne['workout_count'], 2);
        expect(dayOne['workout_minutes'], 50.0);
        expect(dayOne['workout_distance_km'], 13.0);
        final dayTwo = days.firstWhere(
          (d) => (d as Map)['date'] == '2026-05-26',
        ) as Map;
        expect(dayTwo['workout_count'], 1);
        expect(dayTwo['workout_minutes'], 60.0);
        expect(dayTwo['workout_distance_km'], isNull,
            reason: 'strength training has no distance payload');

        final summary = out['summary'] as Map<String, Object?>;
        expect(summary['workout_count'], 3);
        expect(summary['workout_total_minutes'], 110.0);
        expect(summary['workout_total_distance_km'], 13.0);
      },
    );

    test('drops rows outside the window', () {
      final old = DateTime.utc(2026, 4, 1);
      final inWin = DateTime.utc(2026, 5, 25);
      final out = GetActivitySummaryTool.shape(
        steps: [
          _metric(
            id: 'old',
            kind: HealthMetricKind.stepsDaily,
            day: old,
            value: 10000,
            unit: 'count',
          ),
          _metric(
            id: 'new',
            kind: HealthMetricKind.stepsDaily,
            day: inWin,
            value: 12000,
            unit: 'count',
          ),
        ],
        energy: const <HealthMetric>[],
        daysBack: 7,
        now: now,
      );
      final days = out['days'] as List;
      expect(days, hasLength(1));
      expect((days.single as Map)['date'], '2026-05-25');
    });
  });

  test('tool advertises the contract', () {
    const tool = GetActivitySummaryTool();
    expect(tool.name, 'get_activity_summary');
    final props =
        (tool.inputSchema['properties'] as Map)['days_back'] as Map;
    expect(props['default'], 7);
    expect(props['maximum'], 90);
  });
}
