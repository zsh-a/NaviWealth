import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/health/ai_tools/get_hrv_trend_tool.dart';
import 'package:naviwealth/features/health/domain/health_metric.dart';
import 'package:naviwealth/features/health/domain/health_metric_kind.dart';

HealthMetric _hrv({
  required String id,
  required DateTime day,
  required double ms,
}) => HealthMetric(
  id: id,
  capturedAt: day,
  kind: HealthMetricKind.hrvDaily,
  value: ms,
  unit: 'ms',
  sync: SyncMeta(
    ownerUserId: 'u',
    updatedAt: day,
    updatedByDevice: 'dev',
    hlc: Hlc(wallMillis: day.millisecondsSinceEpoch, counter: 0, nodeId: 'dev'),
    deletedAt: null,
  ),
);

void main() {
  final now = DateTime.utc(2026, 5, 27, 8);

  group('GetHrvTrendTool.shape', () {
    test('empty rows → note + no summary', () {
      final out = GetHrvTrendTool.shape(
        const <HealthMetric>[],
        windowDays: 30,
        now: now,
      );
      expect(out['points'], isEmpty);
      expect(out['summary'], isNull);
      expect(out['note'], isNotNull);
    });

    test('< 4 samples → summary stripped of delta_pct + note', () {
      // Repo returns rows newest-first; shape sorts oldest-first.
      final rows = [
        _hrv(id: 'd2', day: now.subtract(const Duration(days: 1)), ms: 55),
        _hrv(id: 'd1', day: now.subtract(const Duration(days: 2)), ms: 50),
        _hrv(id: 'd0', day: now.subtract(const Duration(days: 3)), ms: 45),
      ];
      final out = GetHrvTrendTool.shape(rows, windowDays: 30, now: now);
      expect((out['points'] as List), hasLength(3));
      final summary = out['summary'] as Map<String, Object?>;
      expect(summary['latest_ms'], 55);
      expect(summary['delta_pct'], isNull);
      expect(out['note'], isNotNull);
    });

    test('≥ 4 samples → full delta_pct against first half', () {
      // First half avg = (40+42+44+46)/4 = 43; second half avg = (50+52+54+56)/4 = 53.
      // delta_pct = (53-43)/43 * 100 = 23.26.
      final firstHalfDays = [10, 9, 8, 7];
      final secondHalfDays = [4, 3, 2, 1];
      final firstHalfVals = [40.0, 42.0, 44.0, 46.0];
      final secondHalfVals = [50.0, 52.0, 54.0, 56.0];
      final rows = <HealthMetric>[];
      for (var i = 0; i < firstHalfDays.length; i++) {
        rows.add(
          _hrv(
            id: 'f$i',
            day: now.subtract(Duration(days: firstHalfDays[i])),
            ms: firstHalfVals[i],
          ),
        );
      }
      for (var i = 0; i < secondHalfDays.length; i++) {
        rows.add(
          _hrv(
            id: 's$i',
            day: now.subtract(Duration(days: secondHalfDays[i])),
            ms: secondHalfVals[i],
          ),
        );
      }

      final out = GetHrvTrendTool.shape(rows, windowDays: 30, now: now);
      final summary = out['summary'] as Map<String, Object?>;
      expect(summary['first_half_average_ms'], 43);
      expect(summary['second_half_average_ms'], 53);
      final delta = summary['delta_pct'] as double;
      expect(delta, closeTo(23.26, 0.01));
      // latest_ms is the row at day -1 (most recent), value 56
      expect(summary['latest_ms'], 56);
      expect(out['note'], isNull);
    });

    test('drops samples outside the window', () {
      final rows = [
        _hrv(id: 'in', day: now.subtract(const Duration(days: 5)), ms: 50),
        _hrv(id: 'far', day: now.subtract(const Duration(days: 45)), ms: 40),
      ];
      final out = GetHrvTrendTool.shape(rows, windowDays: 30, now: now);
      expect((out['points'] as List), hasLength(1));
    });
  });

  test('tool advertises the contract', () {
    const tool = GetHrvTrendTool();
    expect(tool.name, 'get_hrv_trend');
    final wd = (tool.inputSchema['properties'] as Map)['window_days'] as Map;
    expect(wd['default'], 30);
    expect(wd['enum'], containsAll([7, 14, 30, 60, 90]));
  });
}
