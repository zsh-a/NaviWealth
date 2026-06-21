// D-2.7 sleep-segment merge tests.
//
// `mergeSleepSegments` is a pure function on top of [RawSleepSession]
// so the test stays platform-free (no `health` plugin / Drift). The
// shape of inputs mirrors what iOS HealthKit produces for a single
// night of sleep on Apple Watch (multiple `SLEEP_ASLEEP` segments
// separated by short awake gaps).

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/health/data/health_platform_adapter.dart';

void main() {
  group('mergeSleepSegments', () {
    test('empty input → empty output', () {
      expect(mergeSleepSegments(const <RawSleepSession>[]), isEmpty);
    });

    test('single segment passes through unchanged', () {
      final s = RawSleepSession(
        externalId: 'hk:sleep:s1',
        startedAt: DateTime.utc(2026, 5, 26, 23),
        duration: const Duration(hours: 7),
      );
      final out = mergeSleepSegments([s]);
      expect(out, hasLength(1));
      expect(out.single.externalId, 'hk:sleep:s1');
      expect(out.single.duration, const Duration(hours: 7));
    });

    test('three close segments merge into one merged session', () {
      // Typical Apple Watch night: 23:00–02:30, brief awake, 02:35–05:00,
      // brief awake, 05:05–07:00. Total asleep = 3.5 + 2.42 + 1.92 ≈ 7.83h
      final base = DateTime.utc(2026, 5, 26, 23);
      final segs = <RawSleepSession>[
        RawSleepSession(
          externalId: 'hk:sleep:a',
          startedAt: base,
          duration: const Duration(hours: 3, minutes: 30),
          sourceDevice: 'Apple Watch',
        ),
        RawSleepSession(
          externalId: 'hk:sleep:b',
          startedAt: base.add(const Duration(hours: 3, minutes: 35)),
          duration: const Duration(hours: 2, minutes: 25),
        ),
        RawSleepSession(
          externalId: 'hk:sleep:c',
          startedAt: base.add(const Duration(hours: 6, minutes: 5)),
          duration: const Duration(hours: 1, minutes: 55),
        ),
      ];
      final out = mergeSleepSegments(segs);
      expect(out, hasLength(1));
      final merged = out.single;
      expect(
        merged.duration,
        const Duration(hours: 3, minutes: 30) +
            const Duration(hours: 2, minutes: 25) +
            const Duration(hours: 1, minutes: 55),
      );
      expect(
        merged.startedAt,
        base,
        reason: 'merged session keeps earliest start',
      );
      expect(merged.externalId, contains('merged'));
      expect(merged.externalId, contains(base.toIso8601String()));
      expect(merged.sourceDevice, 'Apple Watch');
      expect(merged.stageHistogramJson, contains('merged_segments'));
      expect(merged.stageHistogramJson, contains('3'));
    });

    test('segments separated by > gap stay as separate sessions', () {
      // 23:00 night sleep + 13:00 afternoon nap. Gap ~ 7h → not merged.
      final night = RawSleepSession(
        externalId: 'hk:sleep:night',
        startedAt: DateTime.utc(2026, 5, 26, 23),
        duration: const Duration(hours: 6),
      );
      final nap = RawSleepSession(
        externalId: 'hk:sleep:nap',
        startedAt: DateTime.utc(2026, 5, 27, 13),
        duration: const Duration(minutes: 45),
      );
      final out = mergeSleepSegments([nap, night]);
      expect(out, hasLength(2));
      expect(
        out.first.externalId,
        'hk:sleep:night',
        reason: 'output sorted by startedAt',
      );
      expect(out.last.externalId, 'hk:sleep:nap');
    });

    test('idempotent: re-merging an already-merged set is stable', () {
      final base = DateTime.utc(2026, 5, 26, 23);
      final segs = <RawSleepSession>[
        RawSleepSession(
          externalId: 'hk:sleep:a',
          startedAt: base,
          duration: const Duration(hours: 4),
        ),
        RawSleepSession(
          externalId: 'hk:sleep:b',
          startedAt: base.add(const Duration(hours: 4, minutes: 10)),
          duration: const Duration(hours: 3),
        ),
      ];
      final first = mergeSleepSegments(segs);
      final second = mergeSleepSegments(first);
      expect(first.length, 1);
      expect(second.length, 1);
      expect(second.single.externalId, first.single.externalId);
      expect(second.single.duration, first.single.duration);
    });

    test('merged id keeps platform prefix from underlying segments', () {
      final base = DateTime.utc(2026, 5, 26, 23);
      final out = mergeSleepSegments([
        RawSleepSession(
          externalId: 'hc:sleep:a',
          startedAt: base,
          duration: const Duration(hours: 4),
        ),
        RawSleepSession(
          externalId: 'hc:sleep:b',
          startedAt: base.add(const Duration(hours: 4, minutes: 10)),
          duration: const Duration(hours: 3),
        ),
      ]);
      expect(out.single.externalId, startsWith('hc:sleep:merged:'));
    });

    test('out-of-order input is sorted before merging', () {
      final base = DateTime.utc(2026, 5, 26, 23);
      final out = mergeSleepSegments([
        RawSleepSession(
          externalId: 'hk:sleep:b',
          startedAt: base.add(const Duration(hours: 4, minutes: 10)),
          duration: const Duration(hours: 3),
        ),
        RawSleepSession(
          externalId: 'hk:sleep:a',
          startedAt: base,
          duration: const Duration(hours: 4),
        ),
      ]);
      expect(out, hasLength(1));
      expect(out.single.startedAt, base);
    });

    test('existing stage histograms are summed while merging', () {
      final base = DateTime.utc(2026, 5, 26, 23);
      final out = mergeSleepSegments([
        RawSleepSession(
          externalId: 'hk:sleep:a',
          startedAt: base,
          duration: const Duration(hours: 3),
          stageHistogramJson: '{"deep":3600,"light":7200}',
        ),
        RawSleepSession(
          externalId: 'hk:sleep:b',
          startedAt: base.add(const Duration(hours: 3, minutes: 5)),
          duration: const Duration(hours: 2),
          stageHistogramJson: '{"rem":1800,"light":5400}',
        ),
      ]);

      final hist =
          jsonDecode(out.single.stageHistogramJson!) as Map<String, Object?>;
      expect(hist['deep'], 3600);
      expect(hist['light'], 12600);
      expect(hist['rem'], 1800);
      expect(hist.containsKey('merged_segments'), isFalse);
    });
  });

  group('mergeSleepStageSegments', () {
    test('aggregates iOS stage segments into one histogrammed session', () {
      final base = DateTime.utc(2026, 5, 26, 23);
      final out = mergeSleepStageSegments([
        RawSleepStageSegment(
          externalId: 'hk:sleep_stage:light-1',
          startedAt: base,
          duration: const Duration(hours: 2),
          stage: 'light',
          sourceDevice: 'Apple Watch',
        ),
        RawSleepStageSegment(
          externalId: 'hk:sleep_stage:deep-1',
          startedAt: base.add(const Duration(hours: 2)),
          duration: const Duration(hours: 1),
          stage: 'deep',
        ),
        RawSleepStageSegment(
          externalId: 'hk:sleep_stage:awake-1',
          startedAt: base.add(const Duration(hours: 3)),
          duration: const Duration(minutes: 10),
          stage: 'awake',
        ),
        RawSleepStageSegment(
          externalId: 'hk:sleep_stage:rem-1',
          startedAt: base.add(const Duration(hours: 3, minutes: 10)),
          duration: const Duration(hours: 2),
          stage: 'rem',
        ),
      ]);

      expect(out, hasLength(1));
      final session = out.single;
      expect(session.startedAt, base);
      expect(session.duration, const Duration(hours: 5));
      expect(session.sourceDevice, 'Apple Watch');
      expect(session.externalId, startsWith('hk:sleep:merged:'));
      final hist =
          jsonDecode(session.stageHistogramJson!) as Map<String, Object?>;
      expect(hist['light'], 7200);
      expect(hist['deep'], 3600);
      expect(hist['rem'], 7200);
      expect(hist['awake'], 600);
    });

    test('awake-only ranges do not create sleep sessions', () {
      final out = mergeSleepStageSegments([
        RawSleepStageSegment(
          externalId: 'hk:sleep_stage:awake-1',
          startedAt: DateTime.utc(2026, 5, 26, 23),
          duration: const Duration(minutes: 15),
          stage: 'awake',
        ),
      ]);

      expect(out, isEmpty);
    });

    test('stage segments separated by more than gap stay separate', () {
      final first = DateTime.utc(2026, 5, 26, 23);
      final second = DateTime.utc(2026, 5, 27, 13);
      final out = mergeSleepStageSegments([
        RawSleepStageSegment(
          externalId: 'hk:sleep_stage:night',
          startedAt: first,
          duration: const Duration(hours: 6),
          stage: 'asleep',
        ),
        RawSleepStageSegment(
          externalId: 'hk:sleep_stage:nap',
          startedAt: second,
          duration: const Duration(minutes: 45),
          stage: 'light',
        ),
      ]);

      expect(out, hasLength(2));
      expect(out.first.startedAt, first);
      expect(out.last.startedAt, second);
    });
  });
}
