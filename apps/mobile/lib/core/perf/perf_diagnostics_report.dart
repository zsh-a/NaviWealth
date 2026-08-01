import 'frame_timing_collector.dart';
import 'perf_trace_recorder.dart';

enum PerfBudgetStatus { insufficientData, passing, failing }

class PerfBudgetPolicy {
  const PerfBudgetPolicy({
    this.minimumFrameCount = 120,
    this.maximumJankRatio = 0.05,
    this.maximumP95BudgetMultiplier = 1,
  });

  final int minimumFrameCount;
  final double maximumJankRatio;
  final double maximumP95BudgetMultiplier;

  PerfBudgetStatus evaluate(FrameStats stats) {
    if (stats.frameCount < minimumFrameCount) {
      return PerfBudgetStatus.insufficientData;
    }
    final p95Limit = stats.frameBudgetUs * maximumP95BudgetMultiplier;
    if (stats.jankRatio > maximumJankRatio || stats.p95TotalUs > p95Limit) {
      return PerfBudgetStatus.failing;
    }
    return PerfBudgetStatus.passing;
  }
}

/// Privacy-safe performance evidence copied from Settings diagnostics.
///
/// The payload contains aggregate timing values and allowlisted stable route
/// trace names only; it never includes route parameters, user data, frame
/// timestamps, or device identifiers.
class PerfDiagnosticsReport {
  PerfDiagnosticsReport({
    required this.generatedAt,
    required this.aggregate,
    required Iterable<PerfTrace> traces,
    this.policy = const PerfBudgetPolicy(),
  }) : traces = List<PerfTrace>.unmodifiable(traces);

  static const int schemaVersion = 1;

  final DateTime generatedAt;
  final FrameStats aggregate;
  final List<PerfTrace> traces;
  final PerfBudgetPolicy policy;

  Map<String, Object?> toJson() => <String, Object?>{
    'schema_version': schemaVersion,
    'generated_at': generatedAt.toUtc().toIso8601String(),
    'policy': <String, Object?>{
      'minimum_frame_count': policy.minimumFrameCount,
      'maximum_jank_ratio': policy.maximumJankRatio,
      'maximum_p95_budget_multiplier': policy.maximumP95BudgetMultiplier,
    },
    'aggregate': _statsJson(aggregate, policy),
    'traces': <Map<String, Object?>>[
      for (final trace in traces)
        <String, Object?>{
          'name': _safeTraceName(trace.name),
          'wall_duration_ms': trace.wallDuration.inMilliseconds,
          'stats': _statsJson(trace.stats, policy),
        },
    ],
  };
}

Map<String, Object?> _statsJson(FrameStats stats, PerfBudgetPolicy policy) =>
    <String, Object?>{
      'status': policy.evaluate(stats).name,
      'frame_count': stats.frameCount,
      'jank_frame_count': stats.jankFrameCount,
      'jank_ratio': stats.jankRatio,
      'frame_budget_us': stats.frameBudgetUs,
      'p50_total_us': stats.p50TotalUs,
      'p95_total_us': stats.p95TotalUs,
      'p95_build_us': stats.p95BuildUs,
      'p95_raster_us': stats.p95RasterUs,
    };

final RegExp _stableRouteTraceName = RegExp(
  r'^route:(push|pop|replace):[A-Za-z0-9_.-]+$',
);

String _safeTraceName(String name) {
  return _stableRouteTraceName.hasMatch(name) ? name : 'redacted';
}
