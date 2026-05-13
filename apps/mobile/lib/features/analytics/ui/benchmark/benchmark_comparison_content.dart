import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../../../../design_system/design_system.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../domain/benchmark/benchmark_comparison.dart';
import 'benchmark_labels.dart';

class BenchmarkComparisonContent extends StatelessWidget {
  const BenchmarkComparisonContent({super.key, required this.result});

  final BenchmarkComparisonResult result;

  @override
  Widget build(BuildContext context) {
    if (result.portfolioPoints.isEmpty &&
        result.benchmarks.every((b) => b.points.isEmpty)) {
      return LayoutBuilder(
        builder: (context, c) => AspectRatio(
          aspectRatio: chartAspectFor(c.maxWidth),
          child: const EmptyChartPlaceholder(),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ComparisonChart(result: result),
        const SizedBox(height: 12),
        _AnnualizedSummary(result: result),
        const SizedBox(height: 8),
        for (final series in result.benchmarks)
          _ExcessRow(result: result, series: series),
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

    return LayoutBuilder(
      builder: (context, c) => SizedBox(
        height: 220,
        child: NwLineChart(
          series: series,
          xAxis: TimeAxis(format: dateFmt, maxLabels: 5),
          yAxis: const ValueAxis(
            format: ValueAxisFormat.decimal,
            fractionDigits: 0,
            maxLabels: 4,
          ),
          aspectRatio: chartAspectFor(c.maxWidth),
          interpolation: ChartInterpolation.linear,
          semanticLabel: l10n.benchmarkComparisonTitle,
        ),
      ),
    );
  }
}

class _AnnualizedSummary extends StatelessWidget {
  const _AnnualizedSummary({required this.result});

  final BenchmarkComparisonResult result;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final port = result.portfolioAnnualizedReturn;
    return Row(
      children: [
        Expanded(
          child: Text(
            l10n.benchmarkPortfolioAnnualizedLabel,
            style: context.theme.typography.sm,
          ),
        ),
        Text(
          port == null ? '—' : _formatPercent(port),
          style: context.theme.typography.md.copyWith(
            fontWeight: FontWeight.w600,
            color: port == null
                ? context.theme.colors.mutedForeground
                : (port >= 0
                      ? context.theme.colors.primary
                      : context.theme.colors.destructive),
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
    final l10n = AppLocalizations.of(context);
    final excess = result.excessReturnFor(series.index);
    final benchAnn = series.annualizedReturn;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  benchmarkLabel(l10n, series.index),
                  style: context.theme.typography.sm,
                ),
                Text(
                  l10n.benchmarkAnnualizedSubtitle(
                    benchAnn == null ? '—' : _formatPercent(benchAnn),
                  ),
                  style: context.theme.typography.xs.copyWith(
                    color: context.theme.colors.mutedForeground,
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

class BenchmarkCardSkeleton extends StatelessWidget {
  const BenchmarkCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SkeletonBox(height: 220, radius: 8),
        SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: SkeletonBox(height: 14)),
            SizedBox(width: 12),
            SkeletonBox(width: 80, height: 18),
          ],
        ),
        SizedBox(height: 8),
        SkeletonBox(height: 14),
        SizedBox(height: 4),
        SkeletonBox(height: 14, width: 200),
      ],
    );
  }
}

class BenchmarkCardError extends StatelessWidget {
  const BenchmarkCardError({super.key, required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Text(
          l10n.benchmarkComparisonError('$error'),
          style: context.theme.typography.xs.copyWith(
            color: context.theme.colors.destructive,
          ),
        ),
      ),
    );
  }
}

String _formatPercent(double ratio) {
  final pct = ratio * 100;
  final sign = pct > 0 ? '+' : '';
  return '$sign${pct.toStringAsFixed(2)}%';
}
