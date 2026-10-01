import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/health/data/health_metric_source.dart';
import 'package:naviwealth/features/health/data/recovery_scorer.dart';
import 'package:naviwealth/features/health/domain/health_metric.dart';
import 'package:naviwealth/features/health/domain/health_metric_kind.dart';

final _now = DateTime.utc(2026, 10, 1, 12);
HealthMetric _metric(
  HealthMetricKind kind,
  int days,
  double value, {
  String source = 'hk',
  String device = 'Watch',
  String? method,
  int hours = 0,
}) {
  final at = _now.subtract(Duration(days: days, hours: hours));
  return HealthMetric(
    id: '$source:${kind.wire}:$days:$hours:$device',
    kind: kind,
    value: value,
    unit: kind.defaultUnit,
    capturedAt: at,
    sourceDevice: device,
    payloadJson: method == null ? null : '{"measurement_method":"$method"}',
    sync: SyncMeta(
      ownerUserId: 'user',
      updatedAt: at,
      updatedByDevice: 'device',
      hlc: Hlc(
        wallMillis: at.millisecondsSinceEpoch,
        counter: 0,
        nodeId: 'device',
      ),
    ),
  );
}

void main() {
  const scorer = RecoveryScorer();
  test('algorithm or device switch cannot borrow another HRV baseline', () {
    for (final switched in [
      _metric(HealthMetricKind.hrvDaily, 0, 30, source: 'hc'),
      _metric(HealthMetricKind.hrvDaily, 0, 30, device: 'New Watch'),
      _metric(HealthMetricKind.hrvDaily, 0, 30, method: 'rmssd'),
    ]) {
      final result = scorer.score(
        hrv: [
          switched,
          for (var i = 8; i <= 15; i++)
            _metric(HealthMetricKind.hrvDaily, i, 60),
        ],
        sleep: const [],
        rhr: const [],
        now: _now,
      );
      expect(result.score, isNull);
      expect(result.components.single['status'], 'learning');
      expect(result.components.single['baseline_samples'], 0);
    }
  });
  test('each component needs its own baseline and freshness cannot hide stale inputs', () {
    final result = scorer.score(
      hrv: [
        for (final i in [0, 1, 2, 8, 9, 10, 11, 12])
          _metric(HealthMetricKind.hrvDaily, i, 50),
      ],
      rhr: [
        for (final i in [6, 8, 9, 10, 11, 12])
          _metric(HealthMetricKind.rhrDaily, i, 60),
      ],
      sleep: [_metric(HealthMetricKind.sleepSession, 1, 8 * 3600)],
      now: _now,
    );
    expect(result.freshnessHours, 144);
    expect(result.confidence, 'low');
    expect(result.coverage, 0.33);
    expect(
      result.components.firstWhere((c) => c['metric'] == 'sleep')['included'],
      false,
    );
  });
  test('five readings from one date do not count as five baseline days', () {
    final result = scorer.score(
      hrv: [
        _metric(HealthMetricKind.hrvDaily, 0, 60),
        for (var h = 0; h < 5; h++)
          _metric(HealthMetricKind.hrvDaily, 8, 50, hours: h),
      ],
      sleep: const [],
      rhr: const [],
      now: _now,
    );
    expect(result.score, isNull);
    expect(result.components.single['baseline_samples'], 1);
  });
  test('night sleep and nap sum by wake date and a user goal is explicit', () {
    final result = scorer.score(
      hrv: const [],
      rhr: const [],
      sleep: [
        _metric(HealthMetricKind.sleepSession, 1, 7 * 3600, hours: -8),
        _metric(HealthMetricKind.sleepSession, 0, 3600, hours: 6),
      ],
      sleepGoalHours: 8,
      now: _now,
    );
    expect(result.inputs['avg_sleep_hours'], 8);
    expect(result.components.single['recent_samples'], 1);
    expect(result.components.single['reference_basis'], 'user_goal');
    expect(result.score, 75);
    expect(result.confidence, 'low');
  });
  test('calendar boundary belongs to baseline only', () {
    final result = scorer.score(
      hrv: [
        for (var i = 0; i < 28; i++) _metric(HealthMetricKind.hrvDaily, i, 50),
      ],
      sleep: const [],
      rhr: const [],
      now: _now,
    );
    expect(result.components.single['recent_samples'], 7);
    expect(result.components.single['baseline_samples'], 21);
  });
  test('a future family does not hide past observations and unfinished sleep is excluded', () {
    final result = scorer.score(
      hrv: [
        _metric(HealthMetricKind.hrvDaily, -1, 90, device: 'New Watch'),
        for (var i = 0; i < 28; i++) _metric(HealthMetricKind.hrvDaily, i, 50),
      ],
      sleep: [_metric(HealthMetricKind.sleepSession, 0, 8 * 3600)],
      rhr: const [],
      sleepGoalHours: 8,
      now: _now,
    );
    expect(result.score, 50);
    expect(result.components.single['metric'], 'hrv');
    expect(result.components.single['recent_samples'], 7);
  });
  test('preferred source determines overlapping readings without deleting other sources', () {
    final rows = [
      for (var i = 0; i < 28; i++) ...[
        _metric(HealthMetricKind.hrvDaily, i, 50),
        _metric(HealthMetricKind.hrvDaily, i, 80, source: 'garmin'),
      ],
    ];
    final result = scorer.score(
      hrv: rows,
      sleep: const [],
      rhr: const [],
      preferredSources: const {
        HealthMetricKind.hrvDaily: HealthMetricSource.healthKit,
      },
      now: _now,
    );
    expect(result.inputs['latest_hrv_ms'], 50);
    expect(result.components.single['source_id'], 'healthkit');
    expect(rows.length, 56);
  });
}
