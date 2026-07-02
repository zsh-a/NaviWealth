/// HealthOS Trend surface (`docs/domains/healthos-domain.md` §5, D-2.7).
///
/// Three line charts (HRV / sleep hours / workout minutes) over the
/// last 30 days. Each chart pulls from a dedicated provider that maps
/// `health_metrics` rows into [ChartPoint]s; empty states fall back to
/// a "not enough data" message rather than rendering an empty axis.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/shell_chrome.dart';
import '../../../core/auth/current_user.dart';
import '../../../core/auth/domain_scope.dart';
import '../../../core/auth/providers.dart' as core_auth;
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../composition/health_route_paths.dart';
import '../data/providers.dart';
import '../domain/health_metric.dart';
import '../domain/health_metric_kind.dart';
import 'health_metric_colors.dart';

/// Default window covered by every chart on this page.
const Duration kHealthTrendWindow = Duration(days: 30);

enum TrendGroup { recovery, activity, body }

enum _TrendWindow {
  d7(7),
  d30(30),
  d90(90);

  const _TrendWindow(this.days);
  final int days;
}

class HealthTrendPage extends ConsumerStatefulWidget {
  const HealthTrendPage({
    super.key,
    this.initialGroup = TrendGroup.recovery,
    this.initialWindowDays = 30,
    this.initialMetricKind,
  });

  factory HealthTrendPage.fromQuery(Map<String, String> query) {
    final metricKind = _parseMetricKind(query['metric']);
    return HealthTrendPage(
      initialGroup: metricKind == null
          ? _parseTrendGroup(query['group'])
          : _trendGroupForMetric(metricKind),
      initialWindowDays: _parseTrendWindow(query['window']).days,
      initialMetricKind: metricKind,
    );
  }

  final TrendGroup initialGroup;
  final int initialWindowDays;
  final HealthMetricKind? initialMetricKind;

  @override
  ConsumerState<HealthTrendPage> createState() => _HealthTrendPageState();
}

class _HealthTrendPageState extends ConsumerState<HealthTrendPage> {
  late TrendGroup _group;
  late _TrendWindow _window;
  HealthMetricKind? _metricKind;

  @override
  void initState() {
    super.initState();
    _group = widget.initialGroup;
    _window = _trendWindowForDays(widget.initialWindowDays);
    _metricKind = widget.initialMetricKind;
  }

  @override
  void didUpdateWidget(covariant HealthTrendPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialGroup != widget.initialGroup ||
        oldWidget.initialWindowDays != widget.initialWindowDays ||
        oldWidget.initialMetricKind != widget.initialMetricKind) {
      _group = widget.initialGroup;
      _window = _trendWindowForDays(widget.initialWindowDays);
      _metricKind = widget.initialMetricKind;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final groupData = ref.watch(
      trendGroupChartProvider((group: _group, windowDays: _window.days)),
    );
    final specs = _prioritizeMetric(
      _trendSpecs(l10n, _group),
      metricKind: _metricKind,
    );
    final visibleSpecs = groupData.maybeWhen(
      data: (pointsByKind) {
        final withData = specs
            .where(
              (spec) =>
                  spec.kind == _metricKind ||
                  (pointsByKind[spec.kind]?.length ?? 0) >= 2,
            )
            .toList();
        return withData.isEmpty ? specs : withData;
      },
      orElse: () => specs,
    );
    return ShellTabScaffold(
      title: l10n.healthTrendTitle,
      child: ListView(
        padding: shellTabContentPadding(context),
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final groupPicker = SegmentedRow<TrendGroup>(
                options: TrendGroup.values,
                value: _group,
                labelOf: (g) => _trendGroupLabel(l10n, g),
                onChanged: (value) => _go(context, group: value),
              );
              final windowPicker = SegmentedRow<_TrendWindow>(
                options: _TrendWindow.values,
                value: _window,
                labelOf: (w) => '${w.days}d',
                onChanged: (value) => _go(context, window: value),
              );
              if (constraints.maxWidth < 560) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    groupPicker,
                    const SizedBox(height: AppSpacing.s8),
                    windowPicker,
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: groupPicker),
                  const SizedBox(width: AppSpacing.s12),
                  SizedBox(
                    width: AppControlWidths.segmentedCompact,
                    child: windowPicker,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.s16),
          for (final spec in visibleSpecs) ...[
            FadeSlideIn(
              child: _TrendCard(
                spec: spec,
                points: groupData.whenData((m) => m[spec.kind]),
              ),
            ),
            const SizedBox(height: AppSpacing.s16),
          ],
        ],
      ),
    );
  }

  void _go(BuildContext context, {TrendGroup? group, _TrendWindow? window}) {
    context.go(
      healthTrendPath(
        group: group ?? _group,
        metricKind: group == null ? _metricKind : null,
        windowDays: (window ?? _window).days,
      ),
    );
  }

  static String _trendGroupLabel(AppLocalizations l10n, TrendGroup group) =>
      switch (group) {
        TrendGroup.recovery => l10n.healthTrendGroupRecovery,
        TrendGroup.activity => l10n.healthTrendGroupActivity,
        TrendGroup.body => l10n.healthTrendGroupBody,
      };
}

String healthTrendPath({
  TrendGroup? group,
  HealthMetricKind? metricKind,
  int windowDays = 30,
}) {
  final resolvedGroup =
      group ??
      switch (metricKind) {
        null => TrendGroup.recovery,
        final kind => _trendGroupForMetric(kind),
      };
  final query = <String, String>{};
  if (resolvedGroup != TrendGroup.recovery) query['group'] = resolvedGroup.name;
  if (metricKind != null) query['metric'] = metricKind.wire;
  if (windowDays != 30) query['window'] = windowDays.toString();
  return Uri(
    path: HealthRoutes.trend,
    queryParameters: query.isEmpty ? null : query,
  ).toString();
}

HealthMetricKind? _parseMetricKind(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  final kind = HealthMetricKindX.parse(raw);
  if (kind == HealthMetricKind.unknown) return null;
  return kind;
}

TrendGroup _trendGroupForMetric(HealthMetricKind kind) => switch (kind) {
  HealthMetricKind.workoutSession ||
  HealthMetricKind.stepsDaily ||
  HealthMetricKind.distanceWalkingRunningDaily ||
  HealthMetricKind.activeEnergyDaily ||
  HealthMetricKind.floorsClimbedDaily ||
  HealthMetricKind.trainingLoadDaily ||
  HealthMetricKind.trainingEffectDaily ||
  HealthMetricKind.totalEnergyDaily => TrendGroup.activity,
  HealthMetricKind.weight ||
  HealthMetricKind.bodyFat ||
  HealthMetricKind.vo2Max => TrendGroup.body,
  _ => TrendGroup.recovery,
};

List<_TrendSpec> _prioritizeMetric(
  List<_TrendSpec> specs, {
  required HealthMetricKind? metricKind,
}) {
  if (metricKind == null) return specs;
  final index = specs.indexWhere((spec) => spec.kind == metricKind);
  if (index <= 0) return specs;
  return [specs[index], ...specs.take(index), ...specs.skip(index + 1)];
}

TrendGroup _parseTrendGroup(String? raw) {
  for (final group in TrendGroup.values) {
    if (group.name == raw) return group;
  }
  return TrendGroup.recovery;
}

_TrendWindow _parseTrendWindow(String? raw) {
  final days = int.tryParse(raw ?? '');
  return _trendWindowForDays(days);
}

_TrendWindow _trendWindowForDays(int? days) {
  for (final window in _TrendWindow.values) {
    if (window.days == days) return window;
  }
  return _TrendWindow.d30;
}

class _TrendCard extends StatelessWidget {
  const _TrendCard({required this.spec, required this.points});

  final _TrendSpec spec;
  final AsyncValue<List<ChartPoint>?> points;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final accent = spec.color ?? colors.primary;
    return SoftCard(
      level: SoftCardLevel.raised,
      borderless: true,
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppIconTile(
                icon: spec.icon ?? FLucideIcons.activity,
                color: accent,
              ),
              const SizedBox(width: AppSpacing.s8),
              Expanded(
                child: Text(
                  spec.title,
                  style: context.mutedLabelStyle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              points.when(
                loading: () => const SizedBox.shrink(),
                error: (_, _) => const SizedBox.shrink(),
                data: (pts) {
                  if (pts == null || pts.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  final last = pts.last.y;
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: AppSpacing.s6,
                        height: AppSpacing.s6,
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: AppOpacity.strong),
                          borderRadius: BorderRadius.circular(AppRadius.full),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.s6),
                      Text(
                        _formatLatest(last, spec.kind),
                        style: context.strongRowTitleStyle.copyWith(
                          color: colors.foreground,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
          if (spec.subtitle.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.s6),
            Text(
              spec.subtitle,
              style: context.captionStyle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: AppSpacing.s12),
          // Chart.
          SizedBox(
            height: AppChartHeights.standard,
            child: points.when(
              loading: () => const Center(child: FCircularProgress()),
              error: (e, _) => Center(
                child: Text(
                  AppLocalizations.of(context).healthTrendLoadFailed(''),
                  style: context.captionStyle.copyWith(
                    color: colors.destructive,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              data: (pts) {
                if (pts == null || pts.length < 2) {
                  return Center(
                    child: Text(
                      AppLocalizations.of(context).healthTrendNotEnoughData,
                      style: context.captionStyle,
                    ),
                  );
                }
                return NwLineChart(
                  filled: true,
                  heroDots: true,
                  series: <ChartSeries>[
                    ChartSeries(
                      name: spec.title,
                      points: pts,
                      colorOverride: accent,
                      strokeWidth: AppStroke.branch,
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Format the latest chart value for display in the header.
  static String _formatLatest(double value, HealthMetricKind kind) {
    return switch (kind) {
      HealthMetricKind.sleepSession => '${(value * 10).round() / 10}h',
      HealthMetricKind.distanceWalkingRunningDaily =>
        '${(value * 10).round() / 10}km',
      HealthMetricKind.workoutSession => '${value.round()}m',
      HealthMetricKind.stepsDaily => _formatSteps(value),
      HealthMetricKind.weight ||
      HealthMetricKind.bodyFat => '${(value * 10).round() / 10}',
      _ => value.round().toString(),
    };
  }

  static String _formatSteps(double v) {
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}k';
    return v.round().toString();
  }
}

class _TrendSpec {
  const _TrendSpec({
    required this.title,
    required this.subtitle,
    required this.kind,
    this.icon,
    this.color,
  });

  final String title;
  final String subtitle;
  final HealthMetricKind kind;
  final IconData? icon;
  final Color? color;
}

List<_TrendSpec> _trendSpecs(AppLocalizations l10n, TrendGroup group) =>
    switch (group) {
      TrendGroup.recovery => [
        _TrendSpec(
          title: l10n.healthHrvMetricLabel,
          subtitle: l10n.healthTrendHrvSubtitle,
          kind: HealthMetricKind.hrvDaily,
          icon: FLucideIcons.heartPulse,
          color: HealthMetricColors.hrv,
        ),
        _TrendSpec(
          title: l10n.healthSleepMetricLabel,
          subtitle: l10n.healthTrendSleepSubtitle,
          kind: HealthMetricKind.sleepSession,
          icon: FLucideIcons.moon,
          color: HealthMetricColors.sleep,
        ),
        _TrendSpec(
          title: l10n.healthHeartRateMetricLabel,
          subtitle: l10n.healthTrendHeartRateSubtitle,
          kind: HealthMetricKind.heartRateDaily,
          icon: FLucideIcons.heart,
          color: HealthMetricColors.heartRate,
        ),
        _TrendSpec(
          title: l10n.healthTrendRhrTitle,
          subtitle: l10n.healthTrendRhrSubtitle,
          kind: HealthMetricKind.rhrDaily,
          icon: FLucideIcons.heart,
          color: HealthMetricColors.rhr,
        ),
        _TrendSpec(
          title: l10n.healthTrendSpo2Title,
          subtitle: l10n.healthTrendSpo2Subtitle,
          kind: HealthMetricKind.spo2Daily,
          icon: FLucideIcons.wind,
          color: HealthMetricColors.spo2,
        ),
        _TrendSpec(
          title: l10n.healthTrendRespiratoryTitle,
          subtitle: l10n.healthTrendRespiratorySubtitle,
          kind: HealthMetricKind.respiratoryRateDaily,
          icon: FLucideIcons.wind,
          color: HealthMetricColors.respiratoryRate,
        ),
        _TrendSpec(
          title: l10n.healthTrendBodyBatteryTitle,
          subtitle: l10n.healthTrendBodyBatterySubtitle,
          kind: HealthMetricKind.bodyBatteryDaily,
          icon: FLucideIcons.battery,
          color: HealthMetricColors.bodyBattery,
        ),
        _TrendSpec(
          title: l10n.healthTrendStressTitle,
          subtitle: l10n.healthTrendStressSubtitle,
          kind: HealthMetricKind.stressDaily,
          icon: FLucideIcons.brain,
          color: HealthMetricColors.stress,
        ),
      ],
      TrendGroup.activity => [
        _TrendSpec(
          title: l10n.healthWorkoutMetricLabel,
          subtitle: l10n.healthTrendWorkoutSubtitle,
          kind: HealthMetricKind.workoutSession,
          icon: FLucideIcons.dumbbell,
          color: HealthMetricColors.workout,
        ),
        _TrendSpec(
          title: l10n.healthStepsMetricLabel,
          subtitle: l10n.healthTrendStepsSubtitle,
          kind: HealthMetricKind.stepsDaily,
          icon: FLucideIcons.footprints,
          color: HealthMetricColors.steps,
        ),
        _TrendSpec(
          title: l10n.healthEnergyMetricLabel,
          subtitle: l10n.healthTrendTotalEnergySubtitle,
          kind: HealthMetricKind.activeEnergyDaily,
          icon: FLucideIcons.flame,
          color: HealthMetricColors.totalEnergy,
        ),
        _TrendSpec(
          title: l10n.healthTrendWalkingDistanceTitle,
          subtitle: l10n.healthTrendWalkingDistanceSubtitle,
          kind: HealthMetricKind.distanceWalkingRunningDaily,
          icon: FLucideIcons.mapPin,
          color: HealthMetricColors.walkingDistance,
        ),
        _TrendSpec(
          title: l10n.healthTrendFlightsTitle,
          subtitle: l10n.healthTrendFlightsSubtitle,
          kind: HealthMetricKind.floorsClimbedDaily,
          icon: FLucideIcons.trendingUp,
          color: HealthMetricColors.floors,
        ),
        _TrendSpec(
          title: l10n.healthTrendTrainingLoadTitle,
          subtitle: l10n.healthTrendTrainingLoadSubtitle,
          kind: HealthMetricKind.trainingLoadDaily,
          icon: FLucideIcons.flame,
          color: HealthMetricColors.trainingLoad,
        ),
        _TrendSpec(
          title: l10n.healthTrendTrainingEffectTitle,
          subtitle: l10n.healthTrendTrainingEffectSubtitle,
          kind: HealthMetricKind.trainingEffectDaily,
          icon: FLucideIcons.zap,
          color: HealthMetricColors.trainingEffect,
        ),
        _TrendSpec(
          title: l10n.healthTrendTotalEnergyTitle,
          subtitle: l10n.healthTrendTotalEnergySubtitle,
          kind: HealthMetricKind.totalEnergyDaily,
          icon: FLucideIcons.flame,
          color: HealthMetricColors.totalEnergy,
        ),
      ],
      TrendGroup.body => [
        _TrendSpec(
          title: l10n.healthTrendWeightTitle,
          subtitle: l10n.healthTrendWeightSubtitle,
          kind: HealthMetricKind.weight,
          icon: FLucideIcons.scale,
          color: HealthMetricColors.weight,
        ),
        _TrendSpec(
          title: l10n.healthTrendBodyFatTitle,
          subtitle: l10n.healthTrendBodyFatSubtitle,
          kind: HealthMetricKind.bodyFat,
          icon: FLucideIcons.percent,
          color: HealthMetricColors.bodyFat,
        ),
        _TrendSpec(
          title: l10n.healthTrendVo2MaxTitle,
          subtitle: l10n.healthTrendVo2MaxSubtitle,
          kind: HealthMetricKind.vo2Max,
          icon: FLucideIcons.activity,
          color: HealthMetricColors.vo2Max,
        ),
      ],
    };

/// Kinds for a group, used by the batch provider (no l10n needed).
List<_TrendSpec> _trendSpecsRaw(TrendGroup group) => switch (group) {
  TrendGroup.recovery => [
    const _TrendSpec(title: '', subtitle: '', kind: HealthMetricKind.hrvDaily),
    const _TrendSpec(
      title: '',
      subtitle: '',
      kind: HealthMetricKind.sleepSession,
    ),
    const _TrendSpec(
      title: '',
      subtitle: '',
      kind: HealthMetricKind.heartRateDaily,
    ),
    const _TrendSpec(title: '', subtitle: '', kind: HealthMetricKind.rhrDaily),
    const _TrendSpec(title: '', subtitle: '', kind: HealthMetricKind.spo2Daily),
    const _TrendSpec(
      title: '',
      subtitle: '',
      kind: HealthMetricKind.respiratoryRateDaily,
    ),
    const _TrendSpec(
      title: '',
      subtitle: '',
      kind: HealthMetricKind.bodyBatteryDaily,
    ),
    const _TrendSpec(
      title: '',
      subtitle: '',
      kind: HealthMetricKind.stressDaily,
    ),
  ],
  TrendGroup.activity => [
    const _TrendSpec(
      title: '',
      subtitle: '',
      kind: HealthMetricKind.workoutSession,
    ),
    const _TrendSpec(
      title: '',
      subtitle: '',
      kind: HealthMetricKind.stepsDaily,
    ),
    const _TrendSpec(
      title: '',
      subtitle: '',
      kind: HealthMetricKind.activeEnergyDaily,
    ),
    const _TrendSpec(
      title: '',
      subtitle: '',
      kind: HealthMetricKind.distanceWalkingRunningDaily,
    ),
    const _TrendSpec(
      title: '',
      subtitle: '',
      kind: HealthMetricKind.floorsClimbedDaily,
    ),
    const _TrendSpec(
      title: '',
      subtitle: '',
      kind: HealthMetricKind.trainingLoadDaily,
    ),
    const _TrendSpec(
      title: '',
      subtitle: '',
      kind: HealthMetricKind.trainingEffectDaily,
    ),
    const _TrendSpec(
      title: '',
      subtitle: '',
      kind: HealthMetricKind.totalEnergyDaily,
    ),
  ],
  TrendGroup.body => [
    const _TrendSpec(title: '', subtitle: '', kind: HealthMetricKind.weight),
    const _TrendSpec(title: '', subtitle: '', kind: HealthMetricKind.bodyFat),
    const _TrendSpec(title: '', subtitle: '', kind: HealthMetricKind.vo2Max),
  ],
};

/// Trend series for one kind + window, ordered by [HealthMetric.capturedAt]
/// ascending so the line chart reads left-to-right oldest → newest.
final trendChartProvider = FutureProvider.autoDispose
    .family<List<ChartPoint>, ({HealthMetricKind kind, int windowDays})>((
      ref,
      params,
    ) async {
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
      final cutoff = DateTime.now().toUtc().subtract(
        Duration(days: params.windowDays),
      );
      return _projectToPoints(rows, params.kind, cutoff: cutoff);
    });

/// Batch provider: fetches all metrics for a [TrendGroup] in one query.
/// Returns a map of kind → chart points, so the trend page fires a single
/// DB read per group switch instead of one query per card.
final trendGroupChartProvider = FutureProvider.autoDispose
    .family<
      Map<HealthMetricKind, List<ChartPoint>>,
      ({TrendGroup group, int windowDays})
    >((ref, params) async {
      final optIns = ref.watch(core_auth.domainOptInsProvider).value;
      if (optIns == null || !optIns.contains(DomainScope.health)) {
        return const {};
      }
      final specs = _trendSpecsRaw(params.group);
      final kinds = specs.map((s) => s.kind).toSet();
      final repo = await ref.watch(healthMetricRepositoryProvider.future);
      final userId = await ref.read(currentUserIdProvider)();
      final rowsByKind = await repo.listByKinds(
        ownerUserId: userId,
        kinds: kinds,
        limit: params.windowDays + 50,
      );
      final cutoff = DateTime.now().toUtc().subtract(
        Duration(days: params.windowDays),
      );
      final result = <HealthMetricKind, List<ChartPoint>>{};
      for (final kind in kinds) {
        final rows = rowsByKind[kind] ?? const [];
        result[kind] = _projectToPoints(rows, kind, cutoff: cutoff);
      }
      return result;
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
    case HealthMetricKind.trainingLoadDaily:
    case HealthMetricKind.trainingEffectDaily:
    case HealthMetricKind.spo2Daily:
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
