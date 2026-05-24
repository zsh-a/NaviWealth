import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'frame_timing_collector.dart';
import 'perf_trace_recorder.dart';

/// Process-wide [FrameTimingCollector]. Attaches lazily on first read —
/// pure-Dart unit tests that never read this provider stay decoupled
/// from `SchedulerBinding`.
final frameTimingCollectorProvider = Provider<FrameTimingCollector>((ref) {
  final collector = FrameTimingCollector();
  final binding = SchedulerBinding.instance;
  collector.attach(binding);
  ref.onDispose(() => collector.detach(binding));
  return collector;
});

/// Recorder that resolves named windows against the active
/// [frameTimingCollectorProvider].
final perfTraceRecorderProvider = Provider<PerfTraceRecorder>((ref) {
  return PerfTraceRecorder(collector: ref.watch(frameTimingCollectorProvider));
});
