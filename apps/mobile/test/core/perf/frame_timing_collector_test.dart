import 'dart:ui' show FramePhase;

import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/perf/frame_timing_collector.dart';

FrameTiming _frame({
  required int vsyncStartUs,
  required int totalUs,
  int? buildUs,
  int? rasterUs,
}) {
  // totalSpan = rasterFinish - vsyncStart, so set rasterFinish to land
  // exactly `totalUs` after vsyncStart. buildDuration / rasterDuration
  // each take a third of that span when no override is supplied.
  final third = totalUs ~/ 3;
  final build = buildUs ?? third;
  final raster = rasterUs ?? third;
  return FrameTiming(
    vsyncStart: vsyncStartUs,
    buildStart: vsyncStartUs,
    buildFinish: vsyncStartUs + build,
    rasterStart: vsyncStartUs + totalUs - raster,
    rasterFinish: vsyncStartUs + totalUs,
    rasterFinishWallTime: vsyncStartUs + totalUs,
    frameNumber: vsyncStartUs ~/ 16000,
  );
}

void main() {
  group('FrameTimingCollector', () {
    test('ring buffer respects capacity', () {
      final collector = FrameTimingCollector(capacity: 3, frameBudgetUs: 16000);
      collector.ingest([
        for (var i = 0; i < 10; i++)
          _frame(vsyncStartUs: i * 1000, totalUs: 10000),
      ]);
      expect(collector.sampleCount, 3);
      // The oldest 7 are evicted; the surviving sample range starts at
      // index 7 of the input (the first of the last three).
      final survivors = collector.samples.toList();
      expect(
        survivors.first.timestampInMicroseconds(FramePhase.vsyncStart),
        7000,
      );
      expect(
        survivors.last.timestampInMicroseconds(FramePhase.vsyncStart),
        9000,
      );
    });

    test('empty stats report frameCount=0 without crashing', () {
      final stats = FrameTimingCollector(frameBudgetUs: 16000).statsForAll();
      expect(stats.isEmpty, isTrue);
      expect(stats.jankRatio, 0);
      expect(stats.p95TotalUs, 0);
    });

    test('jank counted when total exceeds the frame budget', () {
      final collector = FrameTimingCollector(frameBudgetUs: 16000);
      collector.ingest([
        _frame(vsyncStartUs: 0, totalUs: 8000),
        _frame(vsyncStartUs: 16000, totalUs: 12000),
        _frame(vsyncStartUs: 32000, totalUs: 20000),
        _frame(vsyncStartUs: 48000, totalUs: 24000),
      ]);
      final stats = collector.statsForAll();
      expect(stats.frameCount, 4);
      expect(stats.jankFrameCount, 2);
      expect(stats.jankRatio, closeTo(0.5, 1e-9));
    });

    test('percentile picks the right value at p50 / p95', () {
      final collector = FrameTimingCollector(frameBudgetUs: 16000);
      // 100 frames with monotonically increasing totalSpan from 1000..100000us.
      collector.ingest([
        for (var i = 0; i < 100; i++)
          _frame(vsyncStartUs: i * 16000, totalUs: (i + 1) * 1000),
      ]);
      final stats = collector.statsForAll();
      // p50 lands at the midpoint of ranks 49 / 50 (50,000us + 51,000us).
      expect(stats.p50TotalUs, closeTo(50500, 1));
      // p95: rank = 0.95 * 99 = 94.05 → interpolate between 95,000us and
      // 96,000us at t=0.05 → 95,050us.
      expect(stats.p95TotalUs, closeTo(95050, 1));
    });

    test('statsForWindow only sees frames inside the window', () {
      final collector = FrameTimingCollector(frameBudgetUs: 16000);
      collector.ingest([
        _frame(vsyncStartUs: 0, totalUs: 8000),
        _frame(vsyncStartUs: 16000, totalUs: 12000),
        _frame(vsyncStartUs: 32000, totalUs: 20000),
        _frame(vsyncStartUs: 48000, totalUs: 24000),
      ]);
      final stats = collector.statsForWindow(
        from: const Duration(microseconds: 15000),
        to: const Duration(microseconds: 35000),
      );
      // Two frames live inside [15ms, 35ms]: 16000us + 32000us.
      expect(stats.frameCount, 2);
      // One of them (32000us=20000) exceeds budget.
      expect(stats.jankFrameCount, 1);
    });
  });
}
