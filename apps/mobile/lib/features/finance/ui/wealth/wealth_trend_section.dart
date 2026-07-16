import 'package:decimal/decimal.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/application/read_models/dashboard_providers.dart';
import 'package:naviwealth/features/finance/home/domain/dashboard_time_range.dart';
import 'package:naviwealth/features/finance/home/domain/dashboard_trend_builder.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

/// Historical context for the Wealth hub.
///
/// This is deliberately separate from the Today brief: Today surfaces only
/// the latest change, while Wealth owns the longer-running balance-sheet view.
class WealthTrendSection extends ConsumerStatefulWidget {
  const WealthTrendSection({super.key});

  @override
  ConsumerState<WealthTrendSection> createState() => _WealthTrendSectionState();
}

class _WealthTrendSectionState extends ConsumerState<WealthTrendSection> {
  _WealthTrendMetric _metric = _WealthTrendMetric.netWorth;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final range = ref.watch(dashboardTimeRangeProvider);
    final trendAsync = ref.watch(dashboardTrendProvider(range));
    final baseCurrency = ref.watch(dashboardBaseCurrencyProvider);

    return SoftCard.raised(
      key: const ValueKey('wealth-trend-section'),
      padding: AppPageRhythm.cardPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(l10n.wealthTrendTitle, style: context.labelStyle),
              ),
              AppBadge(
                label: baseCurrency,
                size: AppBadgeSize.compact,
                tone: AppBadgeTone.accent,
              ),
            ],
          ),
          const SizedBox(height: AppPageRhythm.row),
          SegmentedRow<_WealthTrendMetric>(
            options: _WealthTrendMetric.values,
            value: _metric,
            minSegmentWidth: 72,
            labelOf: (metric) => metric.label(l10n),
            onChanged: (metric) => setState(() => _metric = metric),
          ),
          const SizedBox(height: AppPageRhythm.module),
          ContentCrossFade(
            child: KeyedSubtree(
              key: ValueKey(
                'wealth-trend-${_metric.name}-${range.preset.name}',
              ),
              child: trendAsync.when(
                loading: () => const _WealthTrendSkeleton(),
                error: (_, _) => _WealthTrendError(
                  onRetry: () => ref.invalidate(dashboardTrendProvider(range)),
                ),
                data: (trend) =>
                    _WealthTrendBody(trend: trend, metric: _metric),
              ),
            ),
          ),
          const SizedBox(height: AppPageRhythm.module),
          const _WealthTrendRangeSelector(),
        ],
      ),
    );
  }
}

enum _WealthTrendMetric { netWorth, assets, liabilities }

extension on _WealthTrendMetric {
  String label(AppLocalizations l10n) => switch (this) {
    _WealthTrendMetric.netWorth => l10n.homeNetWorthTitle,
    _WealthTrendMetric.assets => l10n.dashboardNetWorthAssetsLabel,
    _WealthTrendMetric.liabilities => l10n.dashboardNetWorthLiabilitiesLabel,
  };

  Decimal valueOf(TrendPoint point) => switch (this) {
    _WealthTrendMetric.netWorth => point.netWorth.amount,
    _WealthTrendMetric.assets => point.assets.amount,
    _WealthTrendMetric.liabilities => point.liabilities.amount,
  };

  SeriesIntent get intent => switch (this) {
    _WealthTrendMetric.netWorth => SeriesIntent.primary,
    _WealthTrendMetric.assets => SeriesIntent.up,
    _WealthTrendMetric.liabilities => SeriesIntent.down,
  };
}

class _WealthTrendBody extends StatelessWidget {
  const _WealthTrendBody({required this.trend, required this.metric});

  final DashboardTrend trend;
  final _WealthTrendMetric metric;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final segments = trend.chartableSegments;
    if (segments.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(
            height: AppChartHeights.standard,
            child: EmptyChartPlaceholder(),
          ),
          const SizedBox(height: AppSpacing.s10),
          Text(
            l10n.wealthTrendIncompleteDisclosure,
            style: context.captionStyle,
          ),
        ],
      );
    }

    // Period delta uses only the trailing complete run so incomplete /
    // estimated lead-ins never invent a fake baseline jump.
    final completeTail = trend.latestCompleteSegment;
    final summaryPoints = completeTail.length >= 2
        ? completeTail
        : segments.last.points;
    final estimatedOnly = completeTail.length < 2;
    final values = [for (final p in summaryPoints) metric.valueOf(p)];
    final allFlat = values.every((value) => value == values.first);

    final seriesName = metric.label(l10n);
    final series = <ChartSeries>[
      for (final segment in segments)
        ChartSeries(
          name: seriesName,
          points: [
            for (final point in segment.points)
              ChartPoint(
                x: point.asOf.millisecondsSinceEpoch.toDouble(),
                y: metric.valueOf(point).toDouble(),
                meta: point,
              ),
          ],
          intent: metric.intent,
          emphasis: segment.isEstimated
              ? SeriesEmphasis.dashed
              : SeriesEmphasis.solid,
          // Soft fill only on reliable solid runs — estimated stays airy.
          fillOpacity: segment.isComplete && !allFlat
              ? AppOpacity.light
              : AppOpacity.transparent,
          strokeWidth: segment.isEstimated ? AppStroke.thin : AppStroke.medium,
        ),
    ];

    // Fit X to real samples only — do not pin to the full selected range
    // (that left a long empty/zero lead-in and a cliff into first funding).
    final dataMinX = series
        .expand((s) => s.points)
        .map((p) => p.x)
        .reduce((a, b) => a < b ? a : b);
    final dataMaxX = series
        .expand((s) => s.points)
        .map((p) => p.x)
        .reduce((a, b) => a > b ? a : b);
    final coverageStartsLate = segments.first.points.first.asOf.isAfter(
      trend.range.from.add(const Duration(days: 2)),
    );
    final hasPartialCoverage =
        segments.length > 1 ||
        segments.any((s) => s.isEstimated) ||
        coverageStartsLate ||
        completeTail.length <
            trend.points
                .where((p) => p.quality != TrendPointQuality.incomplete)
                .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _WealthTrendSummary(
          currency: trend.baseCurrency,
          baseline: !estimatedOnly && values.length > 1 ? values.first : null,
          current: values.last,
        ),
        const SizedBox(height: AppSpacing.s16),
        SizedBox(
          key: const ValueKey('wealth-trend-chart'),
          height: allFlat ? AppChartHeights.standard : AppChartHeights.full,
          child: NwLineChart(
            series: series,
            // Tight fit around real data so short histories fill the plot.
            minX: dataMinX,
            maxX: dataMaxX <= dataMinX ? null : dataMaxX,
            xAxis: TimeAxis(format: _dateFormatFor(trend.range), maxLabels: 4),
            yAxis: ValueAxis.currency(
              currencyCode: trend.baseCurrency,
              maxLabels: 3,
              showGrid: true,
            ),
            // Only solid complete series receive area fill (see fillOpacity).
            filled: !estimatedOnly && !allFlat,
            interpolation: ChartInterpolation.linear,
            showDots: false,
            // End-cap only — resting density stays clean; scrub uses crosshair.
            heroDots: !estimatedOnly && !allFlat,
            showYAxis: false,
            showTouchXAxisLabel: true,
            minimal: allFlat,
            semanticLabel: '${l10n.wealthTrendTitle}, $seriesName',
          ),
        ),
        if (allFlat) ...[
          const SizedBox(height: AppSpacing.s10),
          Text(l10n.wealthTrendFlatHint, style: context.captionStyle),
        ],
        if (hasPartialCoverage) ...[
          const SizedBox(height: AppSpacing.s10),
          Text(
            estimatedOnly
                ? l10n.wealthTrendEstimatedDisclosure
                : l10n.wealthTrendExcludedDisclosure,
            style: context.captionStyle,
          ),
        ],
      ],
    );
  }

  AxisDateFormat _dateFormatFor(DashboardTimeRange range) {
    if (range.spanDays <= 30) return AxisDateFormat.dayMonth;
    if (range.spanDays <= 730) return AxisDateFormat.monthYear;
    return AxisDateFormat.yearOnly;
  }
}

class _WealthTrendSummary extends StatelessWidget {
  const _WealthTrendSummary({
    required this.currency,
    required this.baseline,
    required this.current,
  });

  final String currency;
  final Decimal? baseline;
  final Decimal current;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;
    final delta = baseline == null ? null : current - baseline!;
    final baselineDouble = baseline?.toDouble();
    final ratio = baselineDouble == null || baselineDouble.abs() <= 0
        ? null
        : delta!.toDouble() / baselineDouble.abs();
    final hidden = AmountPrivacyScope.isHiddenOf(context);

    // Keep current + change on one baseline row; compact money stays inline
    // (`¥13.8万`) via MoneyText → AppFormatters.compactCurrency.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _TrendMetricValue(
            label: l10n.dashboardTrendMetricCurrent,
            child: MoneyText(
              amount: current.toDouble(),
              currencyCode: currency,
              compact: true,
              style: TypographyTokens.numericTitleStrong,
            ),
          ),
        ),
        Container(
          width: AppStroke.hairline,
          height: AppSpacing.s48,
          margin: const EdgeInsets.symmetric(horizontal: AppSpacing.s14),
          color: colors.border.withValues(alpha: AppOpacity.highlight),
        ),
        Expanded(
          child: _TrendMetricValue(
            label: l10n.dashboardTrendMetricChange,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (delta == null)
                  Text('—', style: TypographyTokens.numericBodyStrong)
                else
                  DeltaText(
                    value: delta.toDouble(),
                    format: DeltaFormat.currency,
                    currencyCode: currency,
                    fractionDigits: 0,
                    showIcon: false,
                    style: TypographyTokens.numericBodyStrong,
                  ),
                if (ratio != null && !hidden) ...[
                  const SizedBox(height: AppSpacing.s2),
                  DeltaText.percentFromRatio(
                    ratio: ratio,
                    fractionDigits: 1,
                    showIcon: false,
                    style: context.microCaptionStyle,
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _TrendMetricValue extends StatelessWidget {
  const _TrendMetricValue({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: context.microCaptionStyle),
        const SizedBox(height: AppSpacing.s4),
        child,
      ],
    );
  }
}

class _WealthTrendRangeSelector extends ConsumerWidget {
  const _WealthTrendRangeSelector();

  static const _ranges = [
    DashboardRangePreset.m1,
    DashboardRangePreset.m3,
    DashboardRangePreset.y1,
    DashboardRangePreset.y3,
    DashboardRangePreset.all,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final selected = ref.watch(dashboardSelectedRangeProvider);
    return SegmentedRow<DashboardRangePreset>(
      options: _ranges,
      value: selected,
      minSegmentWidth: 44,
      labelOf: (range) => switch (range) {
        DashboardRangePreset.m1 => l10n.dashboardRange1M,
        DashboardRangePreset.m3 => l10n.dashboardRange3M,
        DashboardRangePreset.y1 => l10n.dashboardRange1Y,
        DashboardRangePreset.y3 => l10n.dashboardRange3Y,
        DashboardRangePreset.all => l10n.dashboardRangeAll,
        DashboardRangePreset.m6 => l10n.dashboardRange6M,
        DashboardRangePreset.custom => l10n.dashboardRangeCustom,
      },
      onChanged: (range) {
        ref.read(dashboardCustomRangeProvider.notifier).state = null;
        ref.read(dashboardSelectedRangeProvider.notifier).state = range;
      },
    );
  }
}

class _WealthTrendSkeleton extends StatelessWidget {
  const _WealthTrendSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: SkeletonBox(height: AppSpacing.s48)),
            SizedBox(width: AppSpacing.s16),
            Expanded(child: SkeletonBox(height: AppSpacing.s48)),
          ],
        ),
        SizedBox(height: AppSpacing.s16),
        SkeletonBox(height: AppChartHeights.full),
      ],
    );
  }
}

class _WealthTrendError extends StatelessWidget {
  const _WealthTrendError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SizedBox(
      height: AppChartHeights.standard,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.commonLoadFailed, style: context.bodyCaptionStyle),
            const SizedBox(height: AppSpacing.s8),
            FButton(
              variant: FButtonVariant.ghost,
              onPress: onRetry,
              child: Text(l10n.commonRetry),
            ),
          ],
        ),
      ),
    );
  }
}
