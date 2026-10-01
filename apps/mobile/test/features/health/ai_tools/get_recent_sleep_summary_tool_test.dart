import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/health/ai_tools/get_recent_sleep_summary_tool.dart';
import 'package:naviwealth/features/health/data/health_metric_source.dart';
import 'package:naviwealth/features/health/domain/health_metric.dart';
import 'package:naviwealth/features/health/domain/health_metric_kind.dart';

HealthMetric _sleep({
  required String id,
  required DateTime startedAt,
  required double durationSeconds,
  String unit = 's',
  String? sourceDevice,
}) => HealthMetric(
  id: id,
  capturedAt: startedAt,
  kind: HealthMetricKind.sleepSession,
  value: durationSeconds,
  unit: unit,
  sourceDevice: sourceDevice,
  sync: SyncMeta(
    ownerUserId: 'u',
    updatedAt: startedAt,
    updatedByDevice: 'dev',
    hlc: Hlc(
      wallMillis: startedAt.millisecondsSinceEpoch,
      counter: 0,
      nodeId: 'dev',
    ),
    deletedAt: null,
  ),
);

void main() {
  final now = DateTime.utc(2026, 5, 27, 12);

  group('GetRecentSleepSummaryTool.shape', () {
    test('invalid and unfinished sessions do not replace completed sleep', () {
      final start = now.subtract(const Duration(hours: 7, minutes: 30));
      final out = GetRecentSleepSummaryTool.shape(
        [
          _sleep(
            id: 'garmin:unfinished',
            startedAt: start,
            durationSeconds: 8 * 3600,
          ),
          _sleep(
            id: 'hk:completed',
            startedAt: start,
            durationSeconds: 7 * 3600,
          ),
          _sleep(
            id: 'hk:invalid',
            startedAt: start,
            durationSeconds: double.nan,
          ),
        ],
        daysBack: 7,
        now: now,
      );
      expect((out['summary'] as Map)['average_hours'], 7);
      expect(out['sessions'], hasLength(1));
    });
    test('naps sum with night sleep by wake date and source preference deduplicates sessions', () {
      final night = DateTime(2026, 5, 26, 23).toUtc();
      final out = GetRecentSleepSummaryTool.shape(
        [
          _sleep(id: 'hk:night', startedAt: night, durationSeconds: 7 * 3600),
          _sleep(
            id: 'garmin:night',
            startedAt: night,
            durationSeconds: 8 * 3600,
          ),
          _sleep(
            id: 'hk:nap',
            startedAt: DateTime(2026, 5, 27, 10).toUtc(),
            durationSeconds: 3600,
          ),
        ],
        daysBack: 7,
        now: now,
        preferredSource: HealthMetricSource.healthKit,
      );
      final summary = out['summary'] as Map<String, Object?>;
      expect(summary['session_count'], 2);
      expect(summary['observed_days'], 1);
      expect(summary['average_hours'], 8);
      expect(summary['total_hours'], 8);
    });
    test('returns empty payload + note when no rows', () {
      final out = GetRecentSleepSummaryTool.shape(
        const <HealthMetric>[],
        daysBack: 7,
        now: now,
      );
      expect(out['sessions'], isEmpty);
      final summary = out['summary'] as Map<String, Object?>;
      expect(summary['session_count'], 0);
      expect(summary['total_hours'], 0);
      expect(summary['average_hours'], 0);
      expect(out['note'], isNotNull);
    });

    test(
      'aggregates sessions in the window with seconds → hours conversion',
      () {
        final rows = [
          _sleep(
            id: 'a',
            startedAt: now.subtract(const Duration(days: 1)),
            durationSeconds: 28800, // 8h
            sourceDevice: 'Apple Watch',
          ),
          _sleep(
            id: 'b',
            startedAt: now.subtract(const Duration(days: 2)),
            durationSeconds: 25200, // 7h
          ),
        ];
        final out = GetRecentSleepSummaryTool.shape(
          rows,
          daysBack: 7,
          now: now,
        );
        final sessions = (out['sessions'] as List).cast<Map<String, Object?>>();
        expect(sessions, hasLength(2));
        expect(sessions.first['duration_hours'], 8.0);
        expect(sessions.first['source_device'], 'Apple Watch');
        expect(sessions.last['duration_hours'], 7.0);

        final summary = out['summary'] as Map<String, Object?>;
        expect(summary['session_count'], 2);
        expect(summary['total_hours'], 15.0);
        expect(summary['average_hours'], 7.5);
        expect(out['note'], isNull);
      },
    );

    test('drops sessions outside the requested window', () {
      final rows = [
        _sleep(
          id: 'in-window',
          startedAt: now.subtract(const Duration(days: 1)),
          durationSeconds: 28800,
        ),
        _sleep(
          id: 'too-old',
          startedAt: now.subtract(const Duration(days: 30)),
          durationSeconds: 28800,
        ),
      ];
      final out = GetRecentSleepSummaryTool.shape(rows, daysBack: 7, now: now);
      final sessions = out['sessions'] as List;
      expect(sessions, hasLength(1));
      expect((sessions.single as Map)['duration_hours'], 8.0);
    });

    test('honours alternate unit strings (min, h)', () {
      final rows = [
        _sleep(
          id: 'min',
          startedAt: now.subtract(const Duration(days: 1)),
          durationSeconds: 480,
          unit: 'min',
        ),
        _sleep(
          id: 'h',
          startedAt: now.subtract(const Duration(days: 2)),
          durationSeconds: 6.5,
          unit: 'h',
        ),
      ];
      final out = GetRecentSleepSummaryTool.shape(rows, daysBack: 7, now: now);
      final sessions = (out['sessions'] as List).cast<Map<String, Object?>>();
      expect(sessions.first['duration_hours'], 8.0); // 480 min = 8 h
      expect(sessions.last['duration_hours'], 6.5);
    });

    test('schema fields land on the wire', () {
      final out = GetRecentSleepSummaryTool.shape(
        const <HealthMetric>[],
        daysBack: 7,
        now: now,
      );
      expect(out.containsKey('from'), isTrue);
      expect(out.containsKey('to'), isTrue);
      expect(out.containsKey('sessions'), isTrue);
      expect(out.containsKey('summary'), isTrue);
    });
  });

  test('tool advertises the contract', () {
    const tool = GetRecentSleepSummaryTool();
    expect(tool.name, 'get_recent_sleep_summary');
    final props = (tool.inputSchema['properties'] as Map)['days_back'] as Map;
    expect(props['default'], 7);
    expect(props['maximum'], 90);
  });
}
