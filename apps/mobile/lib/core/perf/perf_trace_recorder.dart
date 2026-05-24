import 'package:flutter/scheduler.dart';

import 'frame_timing_collector.dart';

/// Records named time windows ("opening Wealth tab", "rebalance preview")
/// and resolves them into [PerfTrace]s using frame timings the
/// [FrameTimingCollector] has been gathering for the entire process.
///
/// Single trace at a time per recorder instance — nested perf work
/// either reuses the active trace (caller passes the existing id) or
/// constructs a separate recorder.
class PerfTraceRecorder {
  PerfTraceRecorder({
    required this.collector,
    DateTime Function()? clock,
    Duration Function()? frameClock,
  })  : _wallClock = clock ?? DateTime.now,
        _frameClock = frameClock ?? _defaultFrameClock;

  final FrameTimingCollector collector;
  final DateTime Function() _wallClock;
  final Duration Function() _frameClock;

  _PendingTrace? _active;

  /// Returns the currently running trace name, if any.
  String? get activeName => _active?.name;

  /// Begins a new trace. Throws if one is already active — explicit
  /// teardown forces callers to think about overlap rather than silently
  /// dropping samples.
  void begin(String name) {
    if (_active != null) {
      throw StateError(
        'PerfTraceRecorder: cannot begin "$name" while "${_active!.name}" '
        'is still active. Call end() first.',
      );
    }
    _active = _PendingTrace(
      name: name,
      startedAt: _wallClock(),
      frameStart: _frameClock(),
    );
  }

  /// Ends the active trace and returns the resolved [PerfTrace].
  /// Returns `null` if no trace was running.
  PerfTrace? end() {
    final pending = _active;
    if (pending == null) return null;
    _active = null;
    final wallEnd = _wallClock();
    final frameEnd = _frameClock();
    final stats = collector.statsForWindow(
      from: pending.frameStart,
      to: frameEnd,
    );
    return PerfTrace(
      name: pending.name,
      startedAt: pending.startedAt,
      endedAt: wallEnd,
      stats: stats,
    );
  }

  /// Convenience: run [body] under a trace and return both the trace and
  /// the body's result. End is called even if [body] throws.
  Future<({T result, PerfTrace trace})> measure<T>(
    String name,
    Future<T> Function() body,
  ) async {
    begin(name);
    try {
      final result = await body();
      final trace = end();
      return (result: result, trace: trace!);
    } catch (_) {
      end();
      rethrow;
    }
  }
}

/// Resolved trace returned by [PerfTraceRecorder.end] / .measure.
class PerfTrace {
  const PerfTrace({
    required this.name,
    required this.startedAt,
    required this.endedAt,
    required this.stats,
  });

  final String name;
  final DateTime startedAt;
  final DateTime endedAt;
  final FrameStats stats;

  Duration get wallDuration => endedAt.difference(startedAt);
}

class _PendingTrace {
  _PendingTrace({
    required this.name,
    required this.startedAt,
    required this.frameStart,
  });

  final String name;
  final DateTime startedAt;
  final Duration frameStart;
}

Duration _defaultFrameClock() {
  // SchedulerBinding may be uninitialized in pure-Dart contexts; fall
  // back to zero so callers in tests without a binding don't crash.
  final binding = SchedulerBinding.instance;
  return binding.currentSystemFrameTimeStamp;
}
