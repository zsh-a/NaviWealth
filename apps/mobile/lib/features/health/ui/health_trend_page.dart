/// Health analytics: a compact overview and one focused metric at a time.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../core/format/formatters.dart';
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
import 'health_check_in_sections.dart';
import 'health_metric_detail.dart';
import 'health_metric_presentation.dart';
import 'health_series_chart.dart';
import 'health_source_attention.dart';
import 'health_today_providers.dart';

part 'health_trend_overview.dart';

String _healthSignedPercent(BuildContext context, num value) =>
    AppFormatters(locale: Localizations.localeOf(context))
        .signedPercent(value, decimalDigits: 1);

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
    final navigation = metric == null
        ? SegmentedRow<TrendGroup>.inline(
            options: TrendGroup.values,
            value: group,
            labelOf: (g) => healthGroupLabel(l, g),
            onChanged: (g) => _go(group: g),
          )
        : Align(
            alignment: AlignmentDirectional.centerStart,
            child: AppActionButton(
              variant: FButtonVariant.ghost,
              size: FButtonSizeVariant.md,
              mainAxisSize: MainAxisSize.min,
              hapticIntent: AppInteractionIntent.select,
              prefix: const Icon(FLucideIcons.arrowLeft, size: AppIconSizes.xs),
              onPress: () => _go(group: group),
              child: Flexible(
                child: Text(
                  l.healthAllMetrics,
                  style: context.appTheme.type.numericCaption,
                ),
              ),
            ),
          );
    final range = AppAdaptiveSelectionMenu<int>(
      title: l.healthTimeWindow,
      options: [
        for (final window in const [7, 30, 90])
          AppAdaptiveSelection(
            value: window,
            title: l.healthWindowDays(window),
            icon: FLucideIcons.calendarDays,
          ),
      ],
      value: days,
      onChanged: (window) => _go(window: window, metric: metric),
      triggerBuilder: (context, openMenu, focusNode) => AppActionButton(
        buttonKey: const Key('health-trend-range'),
        variant: FButtonVariant.ghost,
        size: FButtonSizeVariant.md,
        mainAxisSize: MainAxisSize.min,
        hapticIntent: AppInteractionIntent.select,
        semanticsLabel: l.healthWindowDays(days),
        focusNode: focusNode,
        onPress: openMenu,
        child: Flexible(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  l.healthWindowShort(days),
                  style: context.appTheme.type.numericCaptionStrong.copyWith(
                    color: context.theme.colors.primary,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.s6),
              Icon(
                FLucideIcons.chevronDown,
                size: AppIconSizes.xs,
                color: context.theme.colors.mutedForeground,
              ),
            ],
          ),
        ),
      ),
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
              // Category changes keep the toolbar mounted and focused.
              key: PageStorageKey(
                'health-trends-${metric?.wire ?? 'overview'}',
              ),
              padding: shellTabContentPadding(context),
              children: [
                const HealthSourceAttention(),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final scale = MediaQuery.textScalerOf(context).scale(1);
                    var segmentWidth = AppControlHeights.touchTarget;
                    for (final option in TrendGroup.values) {
                      final painter = TextPainter(
                        text: TextSpan(
                          text: healthGroupLabel(l, option),
                          style: context.appTheme.type.numericCaptionStrong,
                        ),
                        textDirection: Directionality.of(context),
                        textScaler: MediaQuery.textScalerOf(context),
                      )..layout();
                      final width =
                          painter.width.ceilToDouble() + AppSpacing.s24;
                      if (width > segmentWidth) segmentWidth = width;
                      painter.dispose();
                    }
                    final minimumNavigationWidth = metric == null
                        ? segmentWidth * TrendGroup.values.length +
                              AppSpacing.s8
                        : 200 * scale;
                    final minimumRangeWidth = 128 * scale;
                    final sideBySide =
                        constraints.maxWidth >=
                        minimumNavigationWidth +
                            minimumRangeWidth +
                            AppSpacing.s12;
                    final rangeWidth = sideBySide
                        ? minimumRangeWidth
                        : constraints.maxWidth;
                    final navigationWidth = sideBySide
                        ? constraints.maxWidth - rangeWidth - AppSpacing.s12
                        : constraints.maxWidth;
                    // Keep both controls in stable slots as they wrap so
                    // resizing and route updates preserve keyboard focus.
                    return Wrap(
                      spacing: AppSpacing.s12,
                      runSpacing: AppSpacing.s8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SizedBox(width: navigationWidth, child: navigation),
                        SizedBox(
                          width: rangeWidth,
                          child: Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: range,
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: AppSpacing.s16),
                Semantics(
                  container: true,
                  child: data.when(
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
                              action: AppActionButton(
                                variant: FButtonVariant.outline,
                                size: FButtonSizeVariant.md,
                                hapticIntent: AppInteractionIntent.select,
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
                            const SizedBox(height: AppSpacing.s12),
                            _TrendPeriodSummary(
                              series: [for (final k in recorded) series[k]!],
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
                ),
                const SizedBox(height: AppSpacing.s24),
                HealthCheckInHistory(days: days),
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
