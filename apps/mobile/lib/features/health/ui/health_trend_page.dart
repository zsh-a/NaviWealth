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

import '../../../core/auth/current_user.dart';
import '../../../core/auth/domain_scope.dart';
import '../../../core/auth/providers.dart' as core_auth;
import '../../../core/shell/shell_chrome.dart';
import '../../../core/shell/shell_visibility.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../composition/health_route_paths.dart';
import '../data/providers.dart';
import '../domain/health_metric.dart';
import '../domain/health_metric_kind.dart';
import 'health_metric_colors.dart';

part 'health_trend_card.dart';
part 'health_trend_providers.dart';
part 'health_trend_specs.dart';

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
      child: ShellTabPause(
        routePath: HealthRoutes.trend,
        child: ListView(
          padding: shellTabContentPadding(context),
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final groupPicker = AppAdaptiveChoice<TrendGroup>(
                  title: l10n.healthTrendTitle,
                  options: TrendGroup.values,
                  value: _group,
                  labelOf: (g) => _trendGroupLabel(l10n, g),
                  inlineMaxOptions: 2,
                  iconOf: (group) => switch (group) {
                    TrendGroup.recovery => FLucideIcons.heartPulse,
                    TrendGroup.activity => FLucideIcons.activity,
                    TrendGroup.body => FLucideIcons.scale,
                  },
                  onChanged: (value) => _go(context, group: value),
                );
                final windowPicker = SegmentedRow<_TrendWindow>(
                  options: _TrendWindow.values,
                  value: _window,
                  minSegmentWidth: 44,
                  labelOf: (w) => '${w.days}d',
                  onChanged: (value) => _go(context, window: value),
                );
                if (constraints.maxWidth < Breakpoints.dialogWide) {
                  return Row(
                    children: [
                      Expanded(flex: 3, child: groupPicker),
                      const SizedBox(width: AppSpacing.s8),
                      Expanded(flex: 2, child: windowPicker),
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
            AdaptiveSummaryGrid(
              items: [
                for (final spec in visibleSpecs)
                  AdaptiveSummaryTile(
                    child: _TrendCard(
                      spec: spec,
                      points: groupData.whenData((m) => m[spec.kind]),
                    ),
                  ),
              ],
            ),
          ],
        ),
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
