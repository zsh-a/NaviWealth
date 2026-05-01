import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/dashboard_providers.dart';
import '../domain/dashboard_models.dart';
import '../domain/dashboard_time_range.dart';
import '../domain/dashboard_trend_builder.dart';

/// Net-worth trend card: time-range chips + line chart.
///
/// The chart and chips watch [dashboardTrendProvider] / the selection
/// providers directly so the UI has no internal state to keep in sync.
class TrendCard extends ConsumerWidget {
  const TrendCard({super.key, required this.snapshot});

  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final trendAsync = ref.watch(dashboardTrendProvider);

    return Card(
      child: Padding(
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
                MoneyText(
                  amount: snapshot.netWorth.amount.toDouble(),
                  currencyCode: snapshot.baseCurrency,
                  style: theme.textTheme.titleMedium,
                  showSign: snapshot.netWorth.isNegative,
                ),
              ],
            ),
            const SizedBox(height: Spacing.s12),
            const _RangeChips(),
            const SizedBox(height: Spacing.s12),
            trendAsync.when(
              loading: () => const _TrendSkeleton(),
              error: (e, st) => _TrendError(error: e),
              data: (trend) => _TrendChart(trend: trend),
            ),
          ],
        ),
      ),
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
    final initialStart = ref.read(dashboardCustomRangeProvider)?.from ??
        now.subtract(const Duration(days: 365));
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange:
          DateTimeRange(start: initialStart, end: initialEnd),
      firstDate: DateTime(now.year - 10),
      lastDate: now,
    );
    if (picked == null) return;
    ref.read(dashboardCustomRangeProvider.notifier).state =
        (from: picked.start, to: picked.end);
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
  const _TrendChart({required this.trend});

  final DashboardTrend trend;

  @override
  Widget build(BuildContext context) {
    if (trend.isEmpty) {
      return const AspectRatio(
        aspectRatio: 16 / 9,
        child: EmptyChartPlaceholder(),
      );
    }
    final allFlat =
        trend.points.every((p) => p.netWorth.amount == trend.points.first.netWorth.amount);
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 220,
          child: NwLineChart(
            series: [series],
            xAxis: TimeAxis(format: dateFmt, maxLabels: 5),
            yAxis: ValueAxis.currency(
              currencyCode: trend.baseCurrency,
              maxLabels: 4,
            ),
            filled: true,
            aspectRatio: 16 / 9,
            semanticLabel: AppLocalizations.of(context).dashboardTrendTitle,
          ),
        ),
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
