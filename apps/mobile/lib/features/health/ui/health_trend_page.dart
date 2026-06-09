/// HealthOS Trend surface (`docs/healthos-domain.md` §5, D-2.7).
///
/// Three line charts (HRV / sleep hours / workout minutes) over the
/// last 30 days. Each chart pulls from a dedicated provider that maps
/// `health_metrics` rows into [ChartPoint]s; empty states fall back to
/// a "not enough data" message rather than rendering an empty axis.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../app/shell_chrome.dart';
import '../../../core/auth/current_user.dart';
import '../../../core/auth/domain_scope.dart';
import '../../../core/auth/providers.dart' as core_auth;
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/providers.dart';
import '../domain/health_metric.dart';
import '../domain/health_metric_kind.dart';

/// Default window covered by every chart on this page.
const Duration kHealthTrendWindow = Duration(days: 30);

enum _TrendGroup { recovery, activity, body }

enum _TrendWindow {
  d7(7),
  d30(30),
  d90(90);

  const _TrendWindow(this.days);
  final int days;
}

class HealthTrendPage extends ConsumerStatefulWidget {
  const HealthTrendPage({super.key});

  @override
  ConsumerState<HealthTrendPage> createState() => _HealthTrendPageState();
}

class _HealthTrendPageState extends ConsumerState<HealthTrendPage> {
  _TrendGroup _group = _TrendGroup.recovery;
  _TrendWindow _window = _TrendWindow.d30;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;
    final typography = context.theme.typography;
    return ShellTabScaffold(
      title: l10n.healthTrendTitle,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.s16),
        children: [
          Row(
            children: [
              Expanded(
                child: SegmentedRow<_TrendGroup>(
                  options: _TrendGroup.values,
                  value: _group,
                  labelOf: (group) => _trendGroupLabel(l10n, group),
                  onChanged: (value) => setState(() => _group = value),
                ),
              ),
              const SizedBox(width: AppSpacing.s8),
              // Compact window toggle
              Container(
                decoration: BoxDecoration(
                  color: colors.muted,
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s4,
                  vertical: AppSpacing.s2,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final w in _TrendWindow.values)
                      _WindowChip(
                        label: '${w.days}d',
                        selected: w == _window,
                        onTap: () => setState(() => _window = w),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s12),
          for (final spec in _trendSpecs(l10n, _group)) ...[
            _TrendCard(spec: spec, windowDays: _window.days),
            const SizedBox(height: AppSpacing.s12),
          ],
        ],
      ),
    );
  }

  static String _trendGroupLabel(AppLocalizations l10n, _TrendGroup group) =>
      switch (group) {
        _TrendGroup.recovery => l10n.healthTrendGroupRecovery,
        _TrendGroup.activity => l10n.healthTrendGroupActivity,
        _TrendGroup.body => l10n.healthTrendGroupBody,
      };
}

class _WindowChip extends StatelessWidget {
  const _WindowChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final typography = context.theme.typography;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s8,
          vertical: AppSpacing.s4,
        ),
        decoration: selected
            ? BoxDecoration(
                color: colors.background,
                borderRadius: BorderRadius.circular(AppRadius.xs),
                boxShadow: [
                  BoxShadow(
                    color: colors.foreground.withValues(alpha: 0.05),
                    blurRadius: 2,
                  ),
                ],
              )
            : null,
        child: Text(
          label,
          style: typography.xs.copyWith(
            color: selected
                ? colors.foreground
                : colors.mutedForeground,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

class _TrendCard extends ConsumerWidget {
  const _TrendCard({required this.spec, required this.windowDays});

  final _TrendSpec spec;
  final int windowDays;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(trendChartProvider((kind: spec.kind, windowDays: windowDays)));
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
          const SizedBox(height: AppSpacing.s2),
          Text(
            spec.subtitle,
            style: context.captionStyle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppSpacing.s12),
          SizedBox(
            height: 160,
            child: async.whenOrLoading(
              error: (e, _) => Center(
                child: Text(
                  AppLocalizations.of(context).healthTrendLoadFailed('$e'),
                  style: typography.xs.copyWith(color: colors.destructive),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              data: (points) {
                if (points.length < 2) {
                  return Center(
                    child: Text(
                      AppLocalizations.of(context).healthTrendNotEnoughData,
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

List<_TrendSpec> _trendSpecs(AppLocalizations l10n, _TrendGroup group) =>
    switch (group) {
      _TrendGroup.recovery => [
        _TrendSpec(
          title: l10n.healthHrvMetricLabel,
          subtitle: l10n.healthTrendHrvSubtitle,
          kind: HealthMetricKind.hrvDaily,
        ),
        _TrendSpec(
          title: l10n.healthSleepMetricLabel,
          subtitle: l10n.healthTrendSleepSubtitle,
          kind: HealthMetricKind.sleepSession,
        ),
        _TrendSpec(
          title: l10n.healthHeartRateMetricLabel,
          subtitle: l10n.healthTrendHeartRateSubtitle,
          kind: HealthMetricKind.heartRateDaily,
        ),
        _TrendSpec(
          title: l10n.healthTrendRespiratoryTitle,
          subtitle: l10n.healthTrendRespiratorySubtitle,
          kind: HealthMetricKind.respiratoryRateDaily,
        ),
        _TrendSpec(
          title: l10n.healthTrendBodyBatteryTitle,
          subtitle: l10n.healthTrendBodyBatterySubtitle,
          kind: HealthMetricKind.bodyBatteryDaily,
        ),
        _TrendSpec(
          title: l10n.healthTrendStressTitle,
          subtitle: l10n.healthTrendStressSubtitle,
          kind: HealthMetricKind.stressDaily,
        ),
      ],
      _TrendGroup.activity => [
        _TrendSpec(
          title: l10n.healthWorkoutMetricLabel,
          subtitle: l10n.healthTrendWorkoutSubtitle,
          kind: HealthMetricKind.workoutSession,
        ),
        _TrendSpec(
          title: l10n.healthStepsMetricLabel,
          subtitle: l10n.healthTrendStepsSubtitle,
          kind: HealthMetricKind.stepsDaily,
        ),
        _TrendSpec(
          title: l10n.healthTrendWalkingDistanceTitle,
          subtitle: l10n.healthTrendWalkingDistanceSubtitle,
          kind: HealthMetricKind.distanceWalkingRunningDaily,
        ),
        _TrendSpec(
          title: l10n.healthTrendFlightsTitle,
          subtitle: l10n.healthTrendFlightsSubtitle,
          kind: HealthMetricKind.floorsClimbedDaily,
        ),
      ],
      _TrendGroup.body => [
        _TrendSpec(
          title: l10n.healthTrendWeightTitle,
          subtitle: l10n.healthTrendWeightSubtitle,
          kind: HealthMetricKind.weight,
        ),
        _TrendSpec(
          title: l10n.healthTrendBodyFatTitle,
          subtitle: l10n.healthTrendBodyFatSubtitle,
          kind: HealthMetricKind.bodyFat,
        ),
        _TrendSpec(
          title: l10n.healthTrendVo2MaxTitle,
          subtitle: l10n.healthTrendVo2MaxSubtitle,
          kind: HealthMetricKind.vo2Max,
        ),
      ],
    };

/// Trend series for one kind + window, ordered by [HealthMetric.capturedAt]
/// ascending so the line chart reads left-to-right oldest → newest.
final trendChartProvider = FutureProvider.autoDispose
    .family<List<ChartPoint>, ({HealthMetricKind kind, int windowDays})>(
        (ref, params) async {
      final optIns = ref.watch(core_auth.domainOptInsProvider).value;
      if (optIns == null || !optIns.contains(DomainScope.health)) {
        return const <ChartPoint>[];
      }
      final repo = await ref.watch(healthMetricRepositoryProvider.future);
      final userId = await ref.read(currentUserIdProvider)();
      final rows = await repo.listByKind(
        ownerUserId: userId,
        kind: params.kind,
        limit: params.windowDays + 50,
      );
      final cutoff =
          DateTime.now().toUtc().subtract(Duration(days: params.windowDays));
      return _projectToPoints(rows, params.kind, cutoff: cutoff);
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
    case HealthMetricKind.stressDaily:
    case HealthMetricKind.bodyBatteryDaily:
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
