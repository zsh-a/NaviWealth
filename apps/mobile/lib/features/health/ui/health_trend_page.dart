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

enum _TrendGroup { recovery, activity, body }

class HealthTrendPage extends ConsumerStatefulWidget {
  const HealthTrendPage({super.key});

  @override
  ConsumerState<HealthTrendPage> createState() => _HealthTrendPageState();
}

class _HealthTrendPageState extends ConsumerState<HealthTrendPage> {
  _TrendGroup _group = _TrendGroup.recovery;

  @override
  Widget build(BuildContext context) {
    return ShellTabScaffold(
      title: '趋势 · HealthOS',
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.s16),
        children: [
          SegmentedRow<_TrendGroup>(
            options: _TrendGroup.values,
            value: _group,
            labelOf: _trendGroupLabel,
            onChanged: (value) => setState(() => _group = value),
          ),
          const SizedBox(height: AppSpacing.s12),
          for (final spec in _trendSpecs(_group)) ...[
            _TrendCard(spec: spec),
            const SizedBox(height: AppSpacing.s12),
          ],
        ],
      ),
    );
  }

  static String _trendGroupLabel(_TrendGroup group) => switch (group) {
    _TrendGroup.recovery => '恢复',
    _TrendGroup.activity => '活动',
    _TrendGroup.body => '身体',
  };
}

class _TrendCard extends ConsumerWidget {
  const _TrendCard({required this.spec});

  final _TrendSpec spec;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(trendChartProvider(spec.kind));
    final typography = context.theme.typography;
    final colors = context.theme.colors;
    return SoftCard(
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            spec.title,
            style: typography.sm.copyWith(fontWeight: FontWeight.w600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            spec.subtitle,
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
                    ChartSeries(name: spec.title, points: points),
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

class _TrendSpec {
  const _TrendSpec({
    required this.title,
    required this.subtitle,
    required this.kind,
  });

  final String title;
  final String subtitle;
  final HealthMetricKind kind;
}

List<_TrendSpec> _trendSpecs(_TrendGroup group) => switch (group) {
  _TrendGroup.recovery => const [
    _TrendSpec(
      title: 'HRV',
      subtitle: '心率变异性（近 30 天）',
      kind: HealthMetricKind.hrvDaily,
    ),
    _TrendSpec(
      title: '睡眠',
      subtitle: '每晚小时数（近 30 天）',
      kind: HealthMetricKind.sleepSession,
    ),
    _TrendSpec(
      title: '心率',
      subtitle: '每日平均心率（近 30 天）',
      kind: HealthMetricKind.heartRateDaily,
    ),
    _TrendSpec(
      title: '呼吸',
      subtitle: '每日平均呼吸率（近 30 天）',
      kind: HealthMetricKind.respiratoryRateDaily,
    ),
  ],
  _TrendGroup.activity => const [
    _TrendSpec(
      title: '运动',
      subtitle: '每天分钟数（近 30 天）',
      kind: HealthMetricKind.workoutSession,
    ),
    _TrendSpec(
      title: '步数',
      subtitle: '每天步数（近 30 天）',
      kind: HealthMetricKind.stepsDaily,
    ),
    _TrendSpec(
      title: '步行距离',
      subtitle: '每天公里数（近 30 天）',
      kind: HealthMetricKind.distanceWalkingRunningDaily,
    ),
    _TrendSpec(
      title: '楼层',
      subtitle: '每天爬楼层数（近 30 天）',
      kind: HealthMetricKind.floorsClimbedDaily,
    ),
  ],
  _TrendGroup.body => const [
    _TrendSpec(
      title: '体重',
      subtitle: '体重记录（近 30 天）',
      kind: HealthMetricKind.weight,
    ),
    _TrendSpec(
      title: '体脂',
      subtitle: '体脂比例（近 30 天）',
      kind: HealthMetricKind.bodyFat,
    ),
    _TrendSpec(
      title: 'VO₂max',
      subtitle: '最大摄氧量（近 30 天）',
      kind: HealthMetricKind.vo2Max,
    ),
  ],
};

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
    case HealthMetricKind.heartRateDaily:
    case HealthMetricKind.totalEnergyDaily:
    case HealthMetricKind.floorsClimbedDaily:
    case HealthMetricKind.respiratoryRateDaily:
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
