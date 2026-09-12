/// Health analytics: a compact overview and one focused metric at a time.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../core/shell/shell_chrome.dart';
import '../../../core/shell/shell_visibility.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../composition/health_route_paths.dart';
import '../composition/health_trend_location.dart';
import '../data/health_series.dart';
import '../data/health_series_providers.dart';
import '../data/providers.dart';
import '../domain/health_metric_kind.dart';
import 'body_measurement_entry_sheet.dart';
import 'garmin_foreground_refresh_scope.dart';
import 'health_metric_detail.dart';
import 'health_metric_presentation.dart';
import 'health_series_chart.dart';
import 'health_source_attention.dart';
import 'health_today_providers.dart';

part 'health_trend_overview.dart';

class HealthTrendPage extends ConsumerStatefulWidget {
  const HealthTrendPage({
    super.key,
    this.initialGroup = TrendGroup.recovery,
    this.initialWindowDays = 30,
    this.initialMetricKind,
  });

  factory HealthTrendPage.fromQuery(Map<String, String> query) {
    final parsed = HealthMetricKindX.parse(query['metric'] ?? '');
    final metric = parsed == HealthMetricKind.unknown ? null : parsed;
    final group = TrendGroup.values
        .where((g) => g.name == query['group'])
        .firstOrNull;
    final days = int.tryParse(query['window'] ?? '');
    return HealthTrendPage(
      initialGroup: metric?.group ?? group ?? TrendGroup.recovery,
      initialWindowDays: const [7, 30, 90].contains(days) ? days! : 30,
      initialMetricKind: metric,
    );
  }

  final TrendGroup initialGroup;
  final int initialWindowDays;
  final HealthMetricKind? initialMetricKind;

  @override
  ConsumerState<HealthTrendPage> createState() => _HealthTrendPageState();
}

class _HealthTrendPageState extends ConsumerState<HealthTrendPage> {
  bool _showMissing = false;

  @override
  void didUpdateWidget(covariant HealthTrendPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialGroup != widget.initialGroup) _showMissing = false;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final group = widget.initialGroup;
    final days = widget.initialWindowDays;
    final metric = widget.initialMetricKind;
    final data = ref.watch(
      healthTrendSeriesProvider((group: group, windowDays: days)),
    );
    return ShellTabScaffold(
      title: metric?.title(l) ?? l.healthTrendTitle,
      actions: group == TrendGroup.body
          ? [
              ShellHeaderActionSpec(
                icon: FLucideIcons.plus,
                label: l.healthRecordBodyMetricAction,
                onPress: () => showBodyMeasurementEntrySheet(
                  context: context,
                  initialKind: metric?.isMeasurement == true
                      ? metric!
                      : HealthMetricKind.weight,
                ),
              ),
            ]
          : const [],
      child: ShellTabPause(
        routePath: HealthRoutes.trend,
        child: GarminForegroundRefreshScope(
          child: AppRefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              key: PageStorageKey(
                'health-trends-${group.name}-${metric?.wire ?? 'overview'}',
              ),
              padding: shellTabContentPadding(context),
              children: [
                const HealthSourceAttention(),
                if (metric == null)
                  SegmentedRow<TrendGroup>(
                    options: TrendGroup.values,
                    value: group,
                    minSegmentWidth: 72,
                    labelOf: (g) => healthGroupLabel(l, g),
                    onChanged: (g) => _go(group: g),
                  )
                else
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: FButton(
                      variant: FButtonVariant.ghost,
                      mainAxisSize: MainAxisSize.min,
                      prefix: const Icon(
                        FLucideIcons.arrowLeft,
                        size: AppIconSizes.sm,
                      ),
                      onPress: () => _go(group: group),
                      child: Flexible(child: Text(l.healthAllMetrics)),
                    ),
                  ),
                const SizedBox(height: AppSpacing.s12),
                SegmentedRow<int>(
                  options: const [7, 30, 90],
                  value: days,
                  minSegmentWidth: 64,
                  labelOf: (d) => l.healthWindowShort(d),
                  semanticLabelOf: (d) => l.healthWindowDays(d),
                  onChanged: (d) => _go(window: d, metric: metric),
                ),
                const SizedBox(height: AppSpacing.s16),
                data.when(
                  skipLoadingOnRefresh: true,
                  skipLoadingOnReload: true,
                  loading: () => const SkeletonCard(
                    child: Column(
                      children: [
                        SkeletonBox(height: 22),
                        SizedBox(height: AppSpacing.s16),
                        SkeletonBox(height: 120),
                      ],
                    ),
                  ),
                  error: (error, stack) => kDefaultError(
                    context,
                    error,
                    stack,
                    onRetry: () => ref.invalidate(
                      healthTrendSeriesProvider((
                        group: group,
                        windowDays: days,
                      )),
                    ),
                  ),
                  data: (series) {
                    if (metric != null && series[metric] != null) {
                      return HealthMetricDetail(series: series[metric]!);
                    }
                    final kinds = healthGroupKinds(group);
                    final recorded = kinds
                        .where((k) => series[k]?.samples.isNotEmpty == true)
                        .toList();
                    final missing = kinds
                        .where((k) => !recorded.contains(k))
                        .toList();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (recorded.isEmpty)
                          AppEmptyState(
                            icon: group == TrendGroup.body
                                ? FLucideIcons.scale
                                : FLucideIcons.activity,
                            title: l.healthNoData,
                            message: l.healthNoRecordsInWindow,
                            compact: true,
                            action: FButton(
                              variant: FButtonVariant.outline,
                              onPress: () => group == TrendGroup.body
                                  ? showBodyMeasurementEntrySheet(
                                      context: context,
                                      initialKind: HealthMetricKind.weight,
                                    )
                                  : context.go(HealthRoutes.today),
                              child: Text(
                                group == TrendGroup.body
                                    ? l.healthRecordBodyMetricAction
                                    : l.healthTodayTitle,
                              ),
                            ),
                          )
                        else ...[
                          _TrendPeriodSummary(
                            series: [for (final k in recorded) series[k]!],
                          ),
                          const SizedBox(height: AppSpacing.s16),
                          AppGroupedSurface(
                            padding: EdgeInsets.zero,
                            child: Column(
                              children: [
                                for (var i = 0; i < recorded.length; i++) ...[
                                  if (i > 0)
                                    const AppGroupedDivider(
                                      indent: AppSpacing.s16,
                                      endIndent: AppSpacing.s16,
                                    ),
                                  _TrendOverviewRow(
                                    series: series[recorded[i]]!,
                                    onPress: () => _go(metric: recorded[i]),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                        if (missing.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.s12),
                          AppRevealControl(
                            expanded: _showMissing,
                            collapsedLabel: l.healthMissingMetrics(
                              missing.length,
                            ),
                            expandedLabel: l.commonRevealLess,
                            onToggle: () =>
                                setState(() => _showMissing = !_showMissing),
                          ),
                          if (_showMissing)
                            for (final k in missing)
                              _MissingMetricRow(
                                kind: k,
                                onPress: () => _go(metric: k),
                              ),
                        ],
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _go({TrendGroup? group, int? window, HealthMetricKind? metric}) =>
      context.go(
        healthTrendPath(
          group: group ?? metric?.group ?? widget.initialGroup,
          metricKind: metric,
          windowDays: window ?? widget.initialWindowDays,
        ),
      );

  Future<void> _refresh() async {
    final coordinator = await ref.read(healthRefreshCoordinatorProvider.future);
    await coordinator.refreshConnectedSources();
    if (!mounted) return;
    ref.invalidate(healthSyncStatusProvider);
    ref.invalidate(healthPlatformStatusProvider);
    ref.invalidate(healthSourceDataSummaryProvider);
    ref.invalidate(healthTodaySnapshotProvider);
    ref.invalidate(healthTrendSeriesProvider);
    await ref.read(
      healthTrendSeriesProvider((
        group: widget.initialGroup,
        windowDays: widget.initialWindowDays,
      )).future,
    );
  }
}
