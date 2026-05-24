import 'dart:collection';
import 'dart:ui' show FramePhase;

import 'package:flutter/scheduler.dart';

import 'refresh_rate.dart';

/// Bounded ring buffer of recent [FrameTiming] samples plus light summary
/// stats. The collector subscribes to `SchedulerBinding.addTimingsCallback`
/// once via [attach] and stays passive otherwise — every operation is
/// constant-time and allocation-free on the hot path.
///
/// Observability M2 (`docs/roadmap-next.md` §4 M-5) uses it as the single
/// source of frame data; [PerfTraceRecorder] layers per-route windows on
/// top so a caller can ask "what did the last 5s of Wealth tab look
/// like" without re-sampling the platform.
class FrameTimingCollector {
  FrameTimingCollector({this.capacity = 600, int? frameBudgetUs})
      : _frameBudgetUs = frameBudgetUs ?? targetFrameBudgetUs();

  /// Max samples to keep. Default holds ~10s of 60fps timing.
  final int capacity;

  final int _frameBudgetUs;

  final Queue<FrameTiming> _samples = Queue<FrameTiming>();
  bool _attached = false;

  /// Read-only view over the currently held samples (oldest first).
  Iterable<FrameTiming> get samples => UnmodifiableListView(_samples.toList());

  int get sampleCount => _samples.length;

  /// Subscribes to platform frame timings. Safe to call multiple times —
  /// only the first call actually attaches the callback.
  void attach(SchedulerBinding binding) {
    if (_attached) return;
    _attached = true;
    binding.addTimingsCallback(_handleTimings);
  }

  /// Removes the platform subscription. Intended for tear-down in tests
  /// or hot-restart.
  void detach(SchedulerBinding binding) {
    if (!_attached) return;
    _attached = false;
    binding.removeTimingsCallback(_handleTimings);
  }

  /// Direct ingestion entry point. Public so tests can feed synthetic
  /// timings without spinning a real binding.
  void ingest(Iterable<FrameTiming> timings) {
    for (final timing in timings) {
      _samples.add(timing);
      if (_samples.length > capacity) {
        _samples.removeFirst();
      }
    }
  }

  void _handleTimings(List<FrameTiming> timings) => ingest(timings);

  /// Snapshot of all currently held frames.
  FrameStats statsForAll() => _statsFor(_samples);

  /// Snapshot restricted to frames whose vsync timestamp falls inside
  /// `[from, to]` (inclusive). Used by [PerfTraceRecorder] to derive a
  /// per-window summary at trace end.
  FrameStats statsForWindow({required Duration from, required Duration to}) {
    final fromUs = from.inMicroseconds;
    final toUs = to.inMicroseconds;
    final filtered = _samples.where((t) {
      final vsync = t.timestampInMicroseconds(FramePhase.vsyncStart);
      return vsync >= fromUs && vsync <= toUs;
    }).toList(growable: false);
    return _statsFor(filtered);
  }

  FrameStats _statsFor(Iterable<FrameTiming> source) {
    final list = source.toList(growable: false);
    if (list.isEmpty) {
      return FrameStats.empty(frameBudgetUs: _frameBudgetUs);
    }
    final totalDurations = list
        .map((t) => t.totalSpan.inMicroseconds)
        .toList(growable: false)
      ..sort();
    final buildDurations = list
        .map((t) => t.buildDuration.inMicroseconds)
        .toList(growable: false)
      ..sort();
    final rasterDurations = list
        .map((t) => t.rasterDuration.inMicroseconds)
        .toList(growable: false)
      ..sort();
    final janky = list
        .where((t) => t.totalSpan.inMicroseconds > _frameBudgetUs)
        .length;
    return FrameStats(
      frameCount: list.length,
      jankFrameCount: janky,
      frameBudgetUs: _frameBudgetUs,
      p50TotalUs: _percentile(totalDurations, 0.50),
      p95TotalUs: _percentile(totalDurations, 0.95),
      p50BuildUs: _percentile(buildDurations, 0.50),
      p95BuildUs: _percentile(buildDurations, 0.95),
      p50RasterUs: _percentile(rasterDurations, 0.50),
      p95RasterUs: _percentile(rasterDurations, 0.95),
    );
  }

  static int _percentile(List<int> sortedAsc, double percentile) {
    assert(sortedAsc.isNotEmpty);
    if (sortedAsc.length == 1) return sortedAsc.first;
    // Linear interpolation between the two surrounding ranks.
    final rank = percentile * (sortedAsc.length - 1);
    final lower = rank.floor();
    final upper = rank.ceil();
    if (lower == upper) return sortedAsc[lower];
    final t = rank - lower;
    return ((sortedAsc[lower] * (1 - t)) + (sortedAsc[upper] * t)).round();
  }
}

/// Aggregated metrics over a set of frames. All durations in microseconds.
class FrameStats {
  const FrameStats({
    required this.frameCount,
    required this.jankFrameCount,
    required this.frameBudgetUs,
    required this.p50TotalUs,
    required this.p95TotalUs,
    required this.p50BuildUs,
    required this.p95BuildUs,
    required this.p50RasterUs,
    required this.p95RasterUs,
  });

  factory FrameStats.empty({required int frameBudgetUs}) {
    return FrameStats(
      frameCount: 0,
      jankFrameCount: 0,
      frameBudgetUs: frameBudgetUs,
      p50TotalUs: 0,
      p95TotalUs: 0,
      p50BuildUs: 0,
      p95BuildUs: 0,
      p50RasterUs: 0,
      p95RasterUs: 0,
    );
  }

  final int frameCount;
  final int jankFrameCount;
  final int frameBudgetUs;
  final int p50TotalUs;
  final int p95TotalUs;
  final int p50BuildUs;
  final int p95BuildUs;
  final int p50RasterUs;
  final int p95RasterUs;

  bool get isEmpty => frameCount == 0;

  double get jankRatio => frameCount == 0 ? 0 : jankFrameCount / frameCount;
}
