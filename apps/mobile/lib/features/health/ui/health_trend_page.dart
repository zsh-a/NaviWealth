/// HealthOS Trend surface (`docs/healthos-domain.md` §5, D-2.7).
///
/// Three line charts (HRV / sleep hours / workout minutes) over the
/// last 30 days. Each chart pulls from a dedicated provider that maps
/// `health_metrics` rows into [ChartPoint]s; empty states fall back to
/// a "not enough data" message rather than rendering an empty axis.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../app/shell_chrome.dart';
import '../../../core/auth/current_user.dart';
import '../../../core/auth/domain_scope.dart';
import '../../../core/auth/providers.dart' as core_auth;
import '../../../design_system/design_system.dart';
import '../data/providers.dart';
import '../domain/health_metric.dart';
import '../domain/health_metric_kind.dart';

/// Window covered by every chart on this page. 30 days mirrors the
/// `get_hrv_trend` tool default + the HealthSyncService initial pull
/// window so the user sees a populated chart on first open.
const Duration kHealthTrendWindow = Duration(days: 30);

class HealthTrendPage extends ConsumerWidget {
  const HealthTrendPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ShellTabScaffold(
      title: '趋势 · HealthOS',
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.s16),
        children: const [
          _TrendCard(
            title: 'HRV',
            subtitle: '心率变异性（近 30 天）',
            kind: HealthMetricKind.hrvDaily,
          ),
          SizedBox(height: AppSpacing.s12),
          _TrendCard(
            title: '睡眠',
            subtitle: '每晚小时数（近 30 天）',
            kind: HealthMetricKind.sleepSession,
          ),
          SizedBox(height: AppSpacing.s12),
          _TrendCard(
            title: '运动',
            subtitle: '每天分钟数（近 30 天）',
            kind: HealthMetricKind.workoutSession,
          ),
          SizedBox(height: AppSpacing.s12),
          _TrendCard(
            title: '步数',
            subtitle: '每天步数（近 30 天）',
            kind: HealthMetricKind.stepsDaily,
          ),
          SizedBox(height: AppSpacing.s12),
          _TrendCard(
            title: '步行距离',
            subtitle: '每天公里数（近 30 天）',
            kind: HealthMetricKind.distanceWalkingRunningDaily,
          ),
        ],
      ),
    );
  }
}

class _TrendCard extends ConsumerWidget {
  const _TrendCard({
    required this.title,
    required this.subtitle,
    required this.kind,
  });

  final String title;
  final String subtitle;
  final HealthMetricKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(trendChartProvider(kind));
    final typography = context.theme.typography;
    final colors = context.theme.colors;
    return SoftCard(
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: typography.sm.copyWith(fontWeight: FontWeight.w600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: typography.xs.copyWith(color: colors.mutedForeground),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppSpacing.s12),
          SizedBox(
            height: 160,
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Text(
                  '加载失败：$e',
                  style: typography.xs.copyWith(color: colors.destructive),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              data: (points) {
                if (points.length < 2) {
                  return Center(
                    child: Text(
                      '数据还不够。',
                      style: typography.xs.copyWith(
                        color: colors.mutedForeground,
                      ),
                    ),
                  );
                }
                return NwLineChart(
                  series: <ChartSeries>[
                    ChartSeries(name: title, points: points),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Trend series for one kind, ordered by [HealthMetric.capturedAt]
/// ascending so the line chart reads left-to-right oldest → newest.
final trendChartProvider = FutureProvider.autoDispose
    .family<List<ChartPoint>, HealthMetricKind>((ref, kind) async {
      final optIns = ref.watch(core_auth.domainOptInsProvider).value;
      if (optIns == null || !optIns.contains(DomainScope.health)) {
        return const <ChartPoint>[];
      }
      final repo = await ref.watch(healthMetricRepositoryProvider.future);
      final userId = await ref.read(currentUserIdProvider)();
      // Generous limit so a busy user (multiple workouts/day) doesn't get
      // clipped. listByKind orders newest-first, the projection re-sorts.
      final rows = await repo.listByKind(
        ownerUserId: userId,
        kind: kind,
        limit: 200,
      );
      final cutoff = DateTime.now().toUtc().subtract(kHealthTrendWindow);
      return _projectToPoints(rows, kind, cutoff: cutoff);
    });

/// Pure projection: rows → ChartPoints. Exposed for unit tests.
@visibleForTesting
List<ChartPoint> healthTrendProject({
  required List<HealthMetric> rows,
  required HealthMetricKind kind,
  required DateTime cutoff,
}) => _projectToPoints(rows, kind, cutoff: cutoff);

List<ChartPoint> _projectToPoints(
  List<HealthMetric> rows,
  HealthMetricKind kind, {
  required DateTime cutoff,
}) {
  switch (kind) {
    case HealthMetricKind.hrvDaily:
    case HealthMetricKind.rhrDaily:
    case HealthMetricKind.stepsDaily:
    case HealthMetricKind.activeEnergyDaily:
    case HealthMetricKind.weight:
    case HealthMetricKind.bodyFat:
    case HealthMetricKind.vo2Max:
      // One row per measurement → one point.
      final pts = <ChartPoint>[];
      for (final r in rows) {
        if (r.capturedAt.isBefore(cutoff)) continue;
        pts.add(
          ChartPoint(
            x: r.capturedAt.toUtc().millisecondsSinceEpoch.toDouble(),
            y: r.value,
          ),
        );
      }
      pts.sort((a, b) => a.x.compareTo(b.x));
      return pts;
    case HealthMetricKind.distanceWalkingRunningDaily:
      // value = meters → km for readability.
      final pts = <ChartPoint>[];
      for (final r in rows) {
        if (r.capturedAt.isBefore(cutoff)) continue;
        pts.add(
          ChartPoint(
            x: r.capturedAt.toUtc().millisecondsSinceEpoch.toDouble(),
            y: r.value / 1000.0,
          ),
        );
      }
      pts.sort((a, b) => a.x.compareTo(b.x));
      return pts;
    case HealthMetricKind.sleepSession:
      // value = seconds → hours.
      final pts = <ChartPoint>[];
      for (final r in rows) {
        if (r.capturedAt.isBefore(cutoff)) continue;
        final hours = switch (r.unit) {
          's' => r.value / 3600.0,
          'min' => r.value / 60.0,
          'h' => r.value,
          _ => r.value / 3600.0,
        };
        pts.add(
          ChartPoint(
            x: r.capturedAt.toUtc().millisecondsSinceEpoch.toDouble(),
            y: hours,
          ),
        );
      }
      pts.sort((a, b) => a.x.compareTo(b.x));
      return pts;
    case HealthMetricKind.workoutSession:
      // Aggregate by UTC day: sum workout minutes per calendar day.
      final byDay = <String, double>{};
      for (final r in rows) {
        if (r.capturedAt.isBefore(cutoff)) continue;
        final key = r.capturedAt.toUtc().toIso8601String().substring(0, 10);
        final minutes = r.value / 60.0;
        byDay.update(key, (v) => v + minutes, ifAbsent: () => minutes);
      }
      final pts = <ChartPoint>[];
      final keys = byDay.keys.toList()..sort();
      for (final k in keys) {
        final parts = k.split('-');
        final dt = DateTime.utc(
          int.parse(parts[0]),
          int.parse(parts[1]),
          int.parse(parts[2]),
        );
        pts.add(
          ChartPoint(x: dt.millisecondsSinceEpoch.toDouble(), y: byDay[k]!),
        );
      }
      return pts;
    case HealthMetricKind.unknown:
      return const <ChartPoint>[];
  }
}
