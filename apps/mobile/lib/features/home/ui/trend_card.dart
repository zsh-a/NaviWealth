import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/dashboard_providers.dart';
import '../domain/dashboard_time_range.dart';
import '../domain/dashboard_trend_builder.dart';
import 'dashboard_chart_fullscreen.dart';

/// Net-worth trend card: time-range chips + line chart.
///
/// The chart and chips watch [dashboardTrendProvider] / the selection
/// providers directly so the UI has no internal state to keep in sync.
class TrendCard extends ConsumerWidget {
  const TrendCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final trendAsync = ref.watch(dashboardTrendProvider);

    return LiquidGlassCard(
      padding: Spacing.cardHero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.dashboardTrendTitle,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              trendAsync.maybeWhen(
                data: (trend) => IconButton(
                  tooltip: l10n.aiChatSheetExpandTooltip,
                  icon: const Icon(Icons.fullscreen),
                  onPressed: trend.isEmpty
                      ? null
                      : () => showDashboardChartFullscreen(
                          context: context,
                          title: l10n.dashboardTrendTitle,
                          child: const _TrendFullscreenContent(),
                        ),
                ),
                orElse: () => const SizedBox(width: 48, height: 48),
              ),
            ],
          ),
          const _RangeChips(),
          const SizedBox(height: Spacing.s12),
          trendAsync.when(
            loading: () => const _TrendSkeleton(),
            error: (e, st) => _TrendError(error: e),
            data: (trend) => _TrendChart(trend: trend),
          ),
        ],
      ),
    );
  }
}

class _TrendFullscreenContent extends ConsumerWidget {
  const _TrendFullscreenContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trendAsync = ref.watch(dashboardTrendProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _RangeChips(),
        const SizedBox(height: Spacing.s16),
        Expanded(
          child: trendAsync.when(
            loading: () => const _TrendSkeleton(),
            error: (e, st) => _TrendError(error: e),
            data: (trend) =>
                _TrendChart(trend: trend, fillAvailableHeight: true),
          ),
        ),
      ],
    );
  }
}

class _RangeChips extends ConsumerWidget {
  const _RangeChips();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final selected = ref.watch(dashboardSelectedRangeProvider);
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final preset in DashboardRangePreset.values)
            Padding(
              padding: const EdgeInsets.only(right: Spacing.s8),
              child: AppChoiceChip(
                label: Text(_rangeLabel(l10n, preset)),
                selected: preset == selected,
                onSelected: (_) => _select(context, ref, preset),
              ),
            ),
        ],
      ),
    );
  }

  void _select(
    BuildContext context,
    WidgetRef ref,
    DashboardRangePreset preset,
  ) {
    if (preset == DashboardRangePreset.custom) {
      _pickCustomRange(context, ref);
      return;
    }
    ref.read(dashboardCustomRangeProvider.notifier).state = null;
    ref.read(dashboardSelectedRangeProvider.notifier).state = preset;
  }

  Future<void> _pickCustomRange(BuildContext context, WidgetRef ref) async {
    final now = DateTime.now();
    final initialEnd = ref.read(dashboardCustomRangeProvider)?.to ?? now;
    final initialStart =
        ref.read(dashboardCustomRangeProvider)?.from ??
        now.subtract(const Duration(days: 365));
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(start: initialStart, end: initialEnd),
      firstDate: DateTime(now.year - 10),
      lastDate: now,
    );
    if (picked == null) return;
    ref.read(dashboardCustomRangeProvider.notifier).state = (
      from: picked.start,
      to: picked.end,
    );
    ref.read(dashboardSelectedRangeProvider.notifier).state =
        DashboardRangePreset.custom;
  }

  String _rangeLabel(AppLocalizations l10n, DashboardRangePreset preset) {
    switch (preset) {
      case DashboardRangePreset.m1:
        return l10n.dashboardRange1M;
      case DashboardRangePreset.m3:
        return l10n.dashboardRange3M;
      case DashboardRangePreset.m6:
        return l10n.dashboardRange6M;
      case DashboardRangePreset.y1:
        return l10n.dashboardRange1Y;
      case DashboardRangePreset.y3:
        return l10n.dashboardRange3Y;
      case DashboardRangePreset.all:
        return l10n.dashboardRangeAll;
      case DashboardRangePreset.custom:
        return l10n.dashboardRangeCustom;
    }
  }
}

class _TrendChart extends StatelessWidget {
  const _TrendChart({required this.trend, this.fillAvailableHeight = false});

  final DashboardTrend trend;
  final bool fillAvailableHeight;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final aspect = chartAspectFor(constraints.maxWidth);
        if (trend.isEmpty) {
          return AspectRatio(
            aspectRatio: aspect,
            child: const EmptyChartPlaceholder(),
          );
        }
        final allFlat = trend.points.every(
          (p) => p.netWorth.amount == trend.points.first.netWorth.amount,
        );
        final theme = Theme.of(context);
        final points = [
          for (final p in trend.points)
            ChartPoint(
              x: p.asOf.millisecondsSinceEpoch.toDouble(),
              y: p.netWorth.amount.toDouble(),
              meta: p,
            ),
        ];
        final series = ChartSeries(name: 'netWorth', points: points);
        final dateFmt = trend.range.spanDays <= 30
            ? AxisDateFormat.dayMonth
            : trend.range.spanDays <= 730
            ? AxisDateFormat.monthYear
            : AxisDateFormat.yearOnly;
        final chart = _LineChartBody(
          series: series,
          trend: trend,
          dateFmt: dateFmt,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (fillAvailableHeight)
              Expanded(child: chart)
            else
              SizedBox(height: 220, child: chart),
            if (allFlat)
              Padding(
                padding: const EdgeInsets.only(top: Spacing.s8),
                child: Text(
                  AppLocalizations.of(context).dashboardTrendFlatHint,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _LineChartBody extends StatelessWidget {
  const _LineChartBody({
    required this.series,
    required this.trend,
    required this.dateFmt,
  });

  final ChartSeries series;
  final DashboardTrend trend;
  final AxisDateFormat dateFmt;

  @override
  Widget build(BuildContext context) {
    return NwLineChart(
      series: [series],
      xAxis: TimeAxis(format: dateFmt, maxLabels: 5),
      yAxis: ValueAxis.currency(
        currencyCode: trend.baseCurrency,
        maxLabels: 4,
        showGrid: true,
      ),
      filled: true,
      heroDots: true,
      showXAxis: false,
      showTouchXAxisLabel: true,
      semanticLabel: AppLocalizations.of(context).dashboardTrendTitle,
    );
  }
}

class _TrendSkeleton extends StatelessWidget {
  const _TrendSkeleton();

  @override
  Widget build(BuildContext context) {
    return const SkeletonBox(height: 220, radius: Radii.sm);
  }
}

class _TrendError extends StatelessWidget {
  const _TrendError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.s24),
      child: Center(
        child: Text(
          l10n.dashboardTrendError('$error'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.error,
          ),
        ),
      ),
    );
  }
}
