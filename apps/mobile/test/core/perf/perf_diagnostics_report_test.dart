import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/perf/frame_timing_collector.dart';
import 'package:naviwealth/core/perf/perf_diagnostics_report.dart';
import 'package:naviwealth/core/perf/perf_trace_recorder.dart';

FrameStats _stats({required int frames, required int jank, required int p95}) =>
    FrameStats(
      frameCount: frames,
      jankFrameCount: jank,
      frameBudgetUs: 8333,
      p50TotalUs: 4000,
      p95TotalUs: p95,
      p50BuildUs: 2000,
      p95BuildUs: 3000,
      p50RasterUs: 1800,
      p95RasterUs: 2800,
    );

void main() {
  const policy = PerfBudgetPolicy();

  test('budget requires a meaningful frame sample', () {
    expect(
      policy.evaluate(_stats(frames: 119, jank: 0, p95: 7000)),
      PerfBudgetStatus.insufficientData,
    );
  });

  test('budget fails on jank ratio or p95 duration', () {
    expect(
      policy.evaluate(_stats(frames: 120, jank: 7, p95: 7000)),
      PerfBudgetStatus.failing,
    );
    expect(
      policy.evaluate(_stats(frames: 120, jank: 0, p95: 9000)),
      PerfBudgetStatus.failing,
    );
  });

  test('report emits bounded aggregate and trace evidence', () {
    final stats = _stats(frames: 240, jank: 2, p95: 8000);
    final report = PerfDiagnosticsReport(
      generatedAt: DateTime.utc(2026, 8, 1, 12),
      aggregate: stats,
      traces: <PerfTrace>[
        PerfTrace(
          name: 'route:push:activity',
          startedAt: DateTime.utc(2026, 8, 1, 11, 59, 59),
          endedAt: DateTime.utc(2026, 8, 1, 12),
          stats: stats,
        ),
        PerfTrace(
          name: 'route:push:/accounts/secret-id',
          startedAt: DateTime.utc(2026, 8, 1, 11, 59, 59),
          endedAt: DateTime.utc(2026, 8, 1, 12),
          stats: stats,
        ),
      ],
    );

    expect(report.toJson(), <String, Object?>{
      'schema_version': 1,
      'generated_at': '2026-08-01T12:00:00.000Z',
      'policy': <String, Object?>{
        'minimum_frame_count': 120,
        'maximum_jank_ratio': 0.05,
        'maximum_p95_budget_multiplier': 1.0,
      },
      'aggregate': <String, Object?>{
        'status': 'passing',
        'frame_count': 240,
        'jank_frame_count': 2,
        'jank_ratio': 2 / 240,
        'frame_budget_us': 8333,
        'p50_total_us': 4000,
        'p95_total_us': 8000,
        'p95_build_us': 3000,
        'p95_raster_us': 2800,
      },
      'traces': <Map<String, Object?>>[
        <String, Object?>{
          'name': 'route:push:activity',
          'wall_duration_ms': 1000,
          'stats': <String, Object?>{
            'status': 'passing',
            'frame_count': 240,
            'jank_frame_count': 2,
            'jank_ratio': 2 / 240,
            'frame_budget_us': 8333,
            'p50_total_us': 4000,
            'p95_total_us': 8000,
            'p95_build_us': 3000,
            'p95_raster_us': 2800,
          },
        },
        <String, Object?>{
          'name': 'redacted',
          'wall_duration_ms': 1000,
          'stats': <String, Object?>{
            'status': 'passing',
            'frame_count': 240,
            'jank_frame_count': 2,
            'jank_ratio': 2 / 240,
            'frame_budget_us': 8333,
            'p50_total_us': 4000,
            'p95_total_us': 8000,
            'p95_build_us': 3000,
            'p95_raster_us': 2800,
          },
        },
      ],
    });
  });
}
