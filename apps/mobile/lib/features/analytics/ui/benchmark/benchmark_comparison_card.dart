import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../design_system/design_system.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../../home/domain/dashboard_time_range.dart';
import '../../data/benchmark/benchmark_providers.dart';
import '../../domain/benchmark/benchmark_comparison.dart';
import '../../domain/benchmark/benchmark_index.dart';

/// Analytics-page card that compares the user's net-worth path against
/// one or more broad-base indices. Selection chips, range chips, the
/// comparison line chart, and the per-benchmark excess-return rows are
/// all stitched off of the providers in `benchmark_providers.dart`.
class BenchmarkComparisonCard extends ConsumerWidget {
  const BenchmarkComparisonCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final resultAsync = ref.watch(benchmarkComparisonResultProvider);

    return Card(
      child: Padding(
        padding: Spacing.cardHero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.benchmarkComparisonTitle,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: Spacing.s4),
            Text(
              l10n.benchmarkComparisonSubtitle,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Spacing.s12),
            const _BenchmarkSelectionChips(),
            const SizedBox(height: Spacing.s12),
            const _BenchmarkRangeChips(),
            const SizedBox(height: Spacing.s16),
            resultAsync.when(
              loading: () => const _CardSkeleton(),
              error: (e, _) => _CardError(error: e),
              data: (result) => _BenchmarkContent(result: result),
            ),
          ],
        ),
      ),
    );
  }
}

class _BenchmarkSelectionChips extends ConsumerWidget {
  const _BenchmarkSelectionChips();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final selection = ref.watch(benchmarkComparisonSelectionProvider);
    return Wrap(
      spacing: Spacing.s8,
      runSpacing: Spacing.s8,
      children: [
        for (final index in BenchmarkIndex.values)
          FilterChip(
            label: Text(benchmarkLabel(l10n, index)),
            selected: selection.contains(index),
            onSelected: (picked) {
              final next = [...selection];
              if (picked) {
                if (!next.contains(index)) next.add(index);
              } else if (next.length > 1) {
                next.remove(index);
              }
              ref.read(benchmarkComparisonSelectionProvider.notifier).state =
                  next;
            },
          ),
      ],
    );
  }
}

class _BenchmarkRangeChips extends ConsumerWidget {
  const _BenchmarkRangeChips();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final selected = ref.watch(benchmarkComparisonRangeProvider);
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final preset in DashboardRangePreset.values)
            Padding(
              padding: const EdgeInsets.only(right: Spacing.s8),
              child: ChoiceChip(
                label: Text(_rangeLabel(l10n, preset)),
                selected: preset == selected,
                onSelected: (_) => _select(context, ref, preset),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _select(
    BuildContext context,
    WidgetRef ref,
    DashboardRangePreset preset,
  ) async {
    if (preset == DashboardRangePreset.custom) {
      await _pickCustomRange(context, ref);
      return;
    }
    ref.read(benchmarkComparisonCustomRangeProvider.notifier).state = null;
    ref.read(benchmarkComparisonRangeProvider.notifier).state = preset;
  }

  Future<void> _pickCustomRange(BuildContext context, WidgetRef ref) async {
    final now = DateTime.now();
    final initialEnd =
        ref.read(benchmarkComparisonCustomRangeProvider)?.to ?? now;
    final initialStart =
        ref.read(benchmarkComparisonCustomRangeProvider)?.from ??
            now.subtract(const Duration(days: 365));
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(start: initialStart, end: initialEnd),
      firstDate: DateTime(now.year - 10),
      lastDate: now,
    );
    if (picked == null) return;
    ref.read(benchmarkComparisonCustomRangeProvider.notifier).state =
        (from: picked.start, to: picked.end);
    ref.read(benchmarkComparisonRangeProvider.notifier).state =
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

class _BenchmarkContent extends StatelessWidget {
  const _BenchmarkContent({required this.result});

  final BenchmarkComparisonResult result;

  @override
  Widget build(BuildContext context) {
    if (result.portfolioPoints.isEmpty &&
        result.benchmarks.every((b) => b.points.isEmpty)) {
      return const AspectRatio(
        aspectRatio: 16 / 9,
        child: EmptyChartPlaceholder(),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ComparisonChart(result: result),
        const SizedBox(height: Spacing.s12),
        _AnnualizedSummary(result: result),
        const SizedBox(height: Spacing.s8),
        for (final series in result.benchmarks) ...[
          _ExcessRow(
            result: result,
            series: series,
          ),
        ],
      ],
    );
  }
}

class _ComparisonChart extends StatelessWidget {
  const _ComparisonChart({required this.result});

  final BenchmarkComparisonResult result;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final spanDays = result.to.difference(result.from).inDays;
    final dateFmt = spanDays <= 30
        ? AxisDateFormat.dayMonth
        : spanDays <= 730
            ? AxisDateFormat.monthYear
            : AxisDateFormat.yearOnly;

    final series = <ChartSeries>[];
    if (result.portfolioPoints.isNotEmpty) {
      series.add(
        ChartSeries(
          name: l10n.benchmarkSeriesPortfolio,
          intent: SeriesIntent.primary,
          points: [
            for (final p in result.portfolioPoints)
              ChartPoint(
                x: p.asOf.millisecondsSinceEpoch.toDouble(),
                y: p.value * 100,
              ),
          ],
        ),
      );
    }
    for (final b in result.benchmarks) {
      if (b.points.isEmpty) continue;
      series.add(
        ChartSeries(
          name: benchmarkLabel(l10n, b.index),
          intent: SeriesIntent.benchmark,
          points: [
            for (final p in b.points)
              ChartPoint(
                x: p.asOf.millisecondsSinceEpoch.toDouble(),
                y: p.value * 100,
              ),
          ],
        ),
      );
    }

    return SizedBox(
      height: 220,
      child: NwLineChart(
        series: series,
        xAxis: TimeAxis(format: dateFmt, maxLabels: 5),
        yAxis: const ValueAxis(
          format: ValueAxisFormat.decimal,
          fractionDigits: 0,
          maxLabels: 4,
        ),
        aspectRatio: 16 / 9,
        semanticLabel: l10n.benchmarkComparisonTitle,
      ),
    );
  }
}

class _AnnualizedSummary extends StatelessWidget {
  const _AnnualizedSummary({required this.result});

  final BenchmarkComparisonResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final port = result.portfolioAnnualizedReturn;
    return Row(
      children: [
        Expanded(
          child: Text(
            l10n.benchmarkPortfolioAnnualizedLabel,
            style: theme.textTheme.bodyMedium,
          ),
        ),
        Text(
          port == null ? '—' : _formatPercent(port),
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: port == null
                ? theme.colorScheme.onSurfaceVariant
                : (port >= 0
                    ? theme.colorScheme.primary
                    : theme.colorScheme.error),
          ),
        ),
      ],
    );
  }
}

class _ExcessRow extends StatelessWidget {
  const _ExcessRow({required this.result, required this.series});

  final BenchmarkComparisonResult result;
  final BenchmarkSeries series;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final excess = result.excessReturnFor(series.index);
    final benchAnn = series.annualizedReturn;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.s4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  benchmarkLabel(l10n, series.index),
                  style: theme.textTheme.bodyMedium,
                ),
                Text(
                  l10n.benchmarkAnnualizedSubtitle(
                    benchAnn == null ? '—' : _formatPercent(benchAnn),
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          DeltaText.percentFromRatio(ratio: excess),
        ],
      ),
    );
  }
}

class _CardSkeleton extends StatelessWidget {
  const _CardSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SkeletonBox(height: 220, radius: Radii.sm),
        SizedBox(height: Spacing.s12),
        Row(
          children: [
            Expanded(child: SkeletonBox(height: 14)),
            SizedBox(width: Spacing.s12),
            SkeletonBox(width: 80, height: 18),
          ],
        ),
        SizedBox(height: Spacing.s8),
        SkeletonBox(height: 14),
        SizedBox(height: Spacing.s4),
        SkeletonBox(height: 14, width: 200),
      ],
    );
  }
}

class _CardError extends StatelessWidget {
  const _CardError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.s24),
      child: Center(
        child: Text(
          l10n.benchmarkComparisonError('$error'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.error,
          ),
        ),
      ),
    );
  }
}

/// Localized chip label for [index]. Top-level so widget tests can assert
/// against the same strings the chart legend uses.
String benchmarkLabel(AppLocalizations l10n, BenchmarkIndex index) {
  switch (index) {
    case BenchmarkIndex.hs300:
      return l10n.benchmarkIndexHs300;
    case BenchmarkIndex.sp500:
      return l10n.benchmarkIndexSp500;
    case BenchmarkIndex.nasdaq:
      return l10n.benchmarkIndexNasdaq;
    case BenchmarkIndex.hsi:
      return l10n.benchmarkIndexHsi;
  }
}

String _formatPercent(double ratio) {
  final pct = ratio * 100;
  final sign = pct > 0 ? '+' : '';
  return '$sign${pct.toStringAsFixed(2)}%';
}
