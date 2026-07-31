import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/health/ai_tools/get_recovery_signal_tool.dart';
import 'package:naviwealth/features/health/domain/health_metric.dart';
import 'package:naviwealth/features/health/domain/health_metric_kind.dart';

HealthMetric _m({
  required HealthMetricKind kind,
  required DateTime at,
  required double value,
  required String unit,
}) => HealthMetric(
  id: '${kind.wire}-${at.millisecondsSinceEpoch}',
  capturedAt: at,
  kind: kind,
  value: value,
  unit: unit,
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

  group('GetRecoverySignalTool.shape', () {
    test('insufficient_data when no baseline', () {
      final out = GetRecoverySignalTool.shape(
        hrv: const <HealthMetric>[],
        sleep: const <HealthMetric>[],
        rhr: const <HealthMetric>[],
        now: now,
      );
      expect(out['score'], isNull);
      expect(out['verdict'], 'insufficient_data');
      expect(out['note'], isNotNull);
    });

    test('insufficient_data when baseline exists but no recent readings', () {
      // 5 baseline days but all > 7 days ago → no recent signal.
      final baseline = <HealthMetric>[
        for (var i = 8; i <= 14; i++)
          _m(
            kind: HealthMetricKind.hrvDaily,
            at: now.subtract(Duration(days: i)),
            value: 50,
            unit: 'ms',
          ),
      ];
      final out = GetRecoverySignalTool.shape(
        hrv: baseline,
        sleep: const <HealthMetric>[],
        rhr: const <HealthMetric>[],
        now: now,
      );
      expect(out['score'], isNull);
      expect(out['verdict'], 'insufficient_data');
    });

    test('rested verdict when HRV ↑ + sleep good + RHR ↓', () {
      // Baseline: 10 days each, recent: improved.
      final hrv = <HealthMetric>[];
      for (var i = 8; i <= 27; i++) {
        hrv.add(
          _m(
            kind: HealthMetricKind.hrvDaily,
            at: now.subtract(Duration(days: i)),
            value: 50,
            unit: 'ms',
          ),
        );
      }
      for (var i = 1; i <= 5; i++) {
        hrv.add(
          _m(
            kind: HealthMetricKind.hrvDaily,
            at: now.subtract(Duration(days: i)),
            value: 65, // +30% over baseline
            unit: 'ms',
          ),
        );
      }

      final rhr = <HealthMetric>[];
      for (var i = 8; i <= 27; i++) {
        rhr.add(
          _m(
            kind: HealthMetricKind.rhrDaily,
            at: now.subtract(Duration(days: i)),
            value: 60,
            unit: 'bpm',
          ),
        );
      }
      for (var i = 1; i <= 5; i++) {
        rhr.add(
          _m(
            kind: HealthMetricKind.rhrDaily,
            at: now.subtract(Duration(days: i)),
            value: 55, // -8% under baseline
            unit: 'bpm',
          ),
        );
      }

      final sleep = <HealthMetric>[];
      for (var i = 1; i <= 5; i++) {
        sleep.add(
          _m(
            kind: HealthMetricKind.sleepSession,
            at: now.subtract(Duration(days: i, hours: 1)),
            value: 8 * 3600.0, // 8h
            unit: 's',
          ),
        );
      }

      final out = GetRecoverySignalTool.shape(
        hrv: hrv,
        sleep: sleep,
        rhr: rhr,
        now: now,
      );
      expect(out['verdict'], 'rested');
      expect(out['score'] as int, greaterThanOrEqualTo(70));
      final inputs = out['inputs'] as Map<String, Object?>;
      expect(inputs['latest_hrv_ms'], 65);
      expect(inputs['avg_sleep_hours'], 8);
      expect(inputs['latest_rhr_bpm'], 55);
      expect(out['confidence'], 'medium');
      expect(out['coverage'], 0.5);
      expect(out['freshness_hours'], 24);
      expect(out['components'], hasLength(3));
      final components = out['components']! as List<Object?>;
      final hrvComponent = components
          .whereType<Map<String, Object?>>()
          .firstWhere((component) => component['metric'] == 'hrv');
      expect(hrvComponent['recent_value'], isNotNull);
      expect(hrvComponent['baseline_value'], isNotNull);
      expect(hrvComponent['delta_pct'], isNotNull);
    });

    test('old and narrow input is explicitly low confidence', () {
      final hrv = <HealthMetric>[
        for (var i = 8; i <= 14; i++)
          _m(
            kind: HealthMetricKind.hrvDaily,
            at: now.subtract(Duration(days: i)),
            value: 50,
            unit: 'ms',
          ),
        _m(
          kind: HealthMetricKind.hrvDaily,
          at: now.subtract(const Duration(days: 6)),
          value: 52,
          unit: 'ms',
        ),
      ];

      final out = GetRecoverySignalTool.shape(
        hrv: hrv,
        sleep: const <HealthMetric>[],
        rhr: const <HealthMetric>[],
        now: now,
      );

      expect(out['score'], isNotNull);
      expect(out['confidence'], 'low');
      expect(out['coverage'], 0.17);
      expect(out['freshness_hours'], 144);
      expect(out['components'], hasLength(1));
    });

    test('strained verdict when HRV ↓ + RHR ↑ + sleep short', () {
      final hrv = <HealthMetric>[];
      for (var i = 8; i <= 27; i++) {
        hrv.add(
          _m(
            kind: HealthMetricKind.hrvDaily,
            at: now.subtract(Duration(days: i)),
            value: 50,
            unit: 'ms',
          ),
        );
      }
      for (var i = 1; i <= 5; i++) {
        hrv.add(
          _m(
            kind: HealthMetricKind.hrvDaily,
            at: now.subtract(Duration(days: i)),
            value: 35, // -30% under baseline
            unit: 'ms',
          ),
        );
      }
      final rhr = <HealthMetric>[];
      for (var i = 8; i <= 27; i++) {
        rhr.add(
          _m(
            kind: HealthMetricKind.rhrDaily,
            at: now.subtract(Duration(days: i)),
            value: 60,
            unit: 'bpm',
          ),
        );
      }
      for (var i = 1; i <= 5; i++) {
        rhr.add(
          _m(
            kind: HealthMetricKind.rhrDaily,
            at: now.subtract(Duration(days: i)),
            value: 68, // +13% over baseline
            unit: 'bpm',
          ),
        );
      }
      final sleep = <HealthMetric>[];
      for (var i = 1; i <= 5; i++) {
        sleep.add(
          _m(
            kind: HealthMetricKind.sleepSession,
            at: now.subtract(Duration(days: i, hours: 1)),
            value: 5.5 * 3600.0, // 5.5h
            unit: 's',
          ),
        );
      }
      final out = GetRecoverySignalTool.shape(
        hrv: hrv,
        sleep: sleep,
        rhr: rhr,
        now: now,
      );
      expect(out['verdict'], 'strained');
      expect(out['score'] as int, lessThan(40));
    });

    test('balanced verdict when signals are mixed', () {
      // HRV slightly up, sleep neutral 7h, RHR flat.
      final hrv = <HealthMetric>[];
      for (var i = 8; i <= 27; i++) {
        hrv.add(
          _m(
            kind: HealthMetricKind.hrvDaily,
            at: now.subtract(Duration(days: i)),
            value: 50,
            unit: 'ms',
          ),
        );
      }
      for (var i = 1; i <= 5; i++) {
        hrv.add(
          _m(
            kind: HealthMetricKind.hrvDaily,
            at: now.subtract(Duration(days: i)),
            value: 52, // +4%
            unit: 'ms',
          ),
        );
      }
      final rhr = <HealthMetric>[];
      for (var i = 1; i <= 27; i++) {
        rhr.add(
          _m(
            kind: HealthMetricKind.rhrDaily,
            at: now.subtract(Duration(days: i)),
            value: 60,
            unit: 'bpm',
          ),
        );
      }
      final sleep = <HealthMetric>[];
      for (var i = 1; i <= 5; i++) {
        sleep.add(
          _m(
            kind: HealthMetricKind.sleepSession,
            at: now.subtract(Duration(days: i, hours: 1)),
            value: 7 * 3600.0,
            unit: 's',
          ),
        );
      }
      final out = GetRecoverySignalTool.shape(
        hrv: hrv,
        sleep: sleep,
        rhr: rhr,
        now: now,
      );
      expect(out['verdict'], 'balanced');
      final score = out['score'] as int;
      expect(score, inInclusiveRange(40, 69));
    });

    test('vo2max improvement contributes to the score', () {
      // No HRV / RHR — only sleep + VO2max so we can isolate the new
      // sub-score's effect.
      final sleep = <HealthMetric>[
        for (var i = 1; i <= 5; i++)
          _m(
            kind: HealthMetricKind.sleepSession,
            at: now.subtract(Duration(days: i, hours: 1)),
            value: 7 * 3600.0, // neutral 7h
            unit: 's',
          ),
      ];
      final vo2 = <HealthMetric>[];
      // baseline: 7 days at 40 ml/kg/min (8..14 days ago)
      for (var i = 8; i <= 14; i++) {
        vo2.add(
          _m(
            kind: HealthMetricKind.vo2Max,
            at: now.subtract(Duration(days: i)),
            value: 40,
            unit: 'ml_kg_min',
          ),
        );
      }
      // recent: 7 days at 48 ml/kg/min (+20%)
      for (var i = 1; i <= 7; i++) {
        vo2.add(
          _m(
            kind: HealthMetricKind.vo2Max,
            at: now.subtract(Duration(days: i)),
            value: 48,
            unit: 'ml_kg_min',
          ),
        );
      }

      final out = GetRecoverySignalTool.shape(
        hrv: const <HealthMetric>[],
        sleep: sleep,
        rhr: const <HealthMetric>[],
        vo2Max: vo2,
        now: now,
      );
      // Sub-score from sleep = 50 (neutral), from VO2max = 50 + 0.20*125 = 75.
      // Mean ≈ 62 → balanced verdict, score > 50.
      expect(out['verdict'], 'balanced');
      final inputs = out['inputs'] as Map<String, Object?>;
      expect(inputs['latest_vo2_max'], 48);
      expect(out['score'] as int, greaterThan(55));
    });
  });

  test('tool advertises the contract', () {
    const tool = GetRecoverySignalTool();
    expect(tool.name, 'get_recovery_signal');
    expect(tool.inputSchema['type'], 'object');
  });
}
