import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/perf/frame_timing_collector.dart';
import 'package:naviwealth/core/perf/perf_trace_recorder.dart';

FrameTiming _frame({required int vsyncStartUs, required int totalUs}) {
  final half = totalUs ~/ 2;
  return FrameTiming(
    vsyncStart: vsyncStartUs,
    buildStart: vsyncStartUs,
    buildFinish: vsyncStartUs + half,
    rasterStart: vsyncStartUs + half,
    rasterFinish: vsyncStartUs + totalUs,
    rasterFinishWallTime: vsyncStartUs + totalUs,
    frameNumber: vsyncStartUs ~/ 16000,
  );
}

void main() {
  group('PerfTraceRecorder', () {
    test('begin/end resolves a window restricted to its frame clock', () {
      final collector = FrameTimingCollector(frameBudgetUs: 16000);
      // Seed frames around an artificial trace window.
      collector.ingest([
        _frame(vsyncStartUs: 0, totalUs: 5000), // before window
        _frame(vsyncStartUs: 16000, totalUs: 5000), // inside
        _frame(vsyncStartUs: 32000, totalUs: 30000), // inside, jank
        _frame(vsyncStartUs: 64000, totalUs: 5000), // after window
      ]);

      var frameNow = const Duration(microseconds: 10000);
      var wallNow = DateTime.utc(2026, 1, 1);
      final recorder = PerfTraceRecorder(
        collector: collector,
        frameClock: () => frameNow,
        clock: () => wallNow,
      );

      recorder.begin('open-wealth');
      expect(recorder.activeName, 'open-wealth');
      // Advance both clocks while frames are accumulating.
      frameNow = const Duration(microseconds: 60000);
      wallNow = wallNow.add(const Duration(milliseconds: 50));
      final trace = recorder.end()!;
      expect(recorder.activeName, isNull);

      expect(trace.name, 'open-wealth');
      expect(trace.stats.frameCount, 2);
      expect(trace.stats.jankFrameCount, 1);
      expect(trace.wallDuration, const Duration(milliseconds: 50));
      expect(recorder.recentTraces.single, same(trace));
    });

    test('end without begin returns null', () {
      final recorder = PerfTraceRecorder(
        collector: FrameTimingCollector(frameBudgetUs: 16000),
      );
      expect(recorder.end(), isNull);
    });

    test('beginning a second trace before the first ends throws', () {
      final recorder = PerfTraceRecorder(
        collector: FrameTimingCollector(frameBudgetUs: 16000),
        frameClock: () => Duration.zero,
        clock: DateTime.now,
      );
      recorder.begin('first');
      expect(() => recorder.begin('second'), throwsStateError);
      recorder.end();
    });

    test('measure ends the trace even when the body throws', () async {
      final recorder = PerfTraceRecorder(
        collector: FrameTimingCollector(frameBudgetUs: 16000),
        frameClock: () => Duration.zero,
        clock: DateTime.now,
      );
      Future<int> failing() async => throw StateError('boom');
      await expectLater(
        recorder.measure('flaky', failing),
        throwsA(isA<StateError>()),
      );
      expect(recorder.activeName, isNull);
    });

    test('measure happy path returns the body result + a trace', () async {
      final recorder = PerfTraceRecorder(
        collector: FrameTimingCollector(frameBudgetUs: 16000),
        frameClock: () => Duration.zero,
        clock: DateTime.now,
      );
      final out = await recorder.measure('ok', () async => 42);
      expect(out.result, 42);
      expect(out.trace.name, 'ok');
    });
  });
}
