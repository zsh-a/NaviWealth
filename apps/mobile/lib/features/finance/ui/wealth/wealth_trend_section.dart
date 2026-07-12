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
    final trendAsync = ref.watch(dashboardTrendProvider);
    final baseCurrency = ref.watch(dashboardBaseCurrencyProvider);

    return SoftCard(
      key: const ValueKey('wealth-trend-section'),
      padding: const EdgeInsets.all(AppSpacing.s16),
      borderRadius: AppRadius.lg,
      level: SoftCardLevel.raised,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(l10n.wealthTrendTitle, style: context.labelStyle),
              ),
              AppBadge(label: baseCurrency, size: AppBadgeSize.compact),
            ],
          ),
          const SizedBox(height: AppSpacing.s12),
          SegmentedRow<_WealthTrendMetric>(
            options: _WealthTrendMetric.values,
            value: _metric,
            minSegmentWidth: 72,
            labelOf: (metric) => metric.label(l10n),
            onChanged: (metric) => setState(() => _metric = metric),
          ),
          const SizedBox(height: AppSpacing.s16),
          AnimatedSwitcher(
            duration: Motion.fast,
            child: trendAsync.when(
              loading: () => const _WealthTrendSkeleton(),
              error: (_, _) => _WealthTrendError(
                onRetry: () => ref.invalidate(dashboardTrendProvider),
              ),
              data: (trend) => _WealthTrendBody(
                key: ValueKey('wealth-trend-${_metric.name}'),
                trend: trend,
                metric: _metric,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.s16),
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
  const _WealthTrendBody({
    super.key,
    required this.trend,
    required this.metric,
  });

  final DashboardTrend trend;
  final _WealthTrendMetric metric;

  @override
  Widget build(BuildContext context) {
    final points = trend.points;
    if (points.isEmpty) {
      return const SizedBox(
        height: AppChartHeights.full,
        child: EmptyChartPlaceholder(),
      );
    }

    final values = [for (final point in points) metric.valueOf(point)];
    final chartPoints = [
      for (var i = 0; i < points.length; i++)
        ChartPoint(
          x: points[i].asOf.millisecondsSinceEpoch.toDouble(),
          y: values[i].toDouble(),
          meta: points[i],
        ),
    ];
    final allFlat = values.every((value) => value == values.first);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _WealthTrendSummary(
          currency: trend.baseCurrency,
          first: values.first,
          last: values.last,
        ),
        const SizedBox(height: AppSpacing.s16),
        SizedBox(
          key: const ValueKey('wealth-trend-chart'),
          height: allFlat ? AppChartHeights.standard : AppChartHeights.full,
          child: NwLineChart(
            series: [
              ChartSeries(
                name: metric.label(AppLocalizations.of(context)),
                points: chartPoints,
                intent: metric.intent,
                fillOpacity: AppOpacity.subtle,
                strokeWidth: AppStroke.medium,
              ),
            ],
            xAxis: TimeAxis(format: _dateFormatFor(trend.range), maxLabels: 4),
            yAxis: ValueAxis.currency(
              currencyCode: trend.baseCurrency,
              maxLabels: 3,
              showGrid: true,
            ),
            filled: !allFlat,
            interpolation: ChartInterpolation.linear,
            showDots: false,
            showYAxis: false,
            showTouchXAxisLabel: true,
            minimal: allFlat,
            semanticLabel:
                '${AppLocalizations.of(context).wealthTrendTitle}, '
                '${metric.label(AppLocalizations.of(context))}',
          ),
        ),
        if (allFlat) ...[
          const SizedBox(height: AppSpacing.s10),
          Text(
            AppLocalizations.of(context).wealthTrendFlatHint,
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
    required this.first,
    required this.last,
  });

  final String currency;
  final Decimal first;
  final Decimal last;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;
    final delta = last - first;
    final firstDouble = first.toDouble();
    final ratio = firstDouble.abs() <= 0
        ? null
        : delta.toDouble() / firstDouble.abs();
    final hidden = AmountPrivacyScope.isHiddenOf(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _TrendMetricValue(
            label: l10n.dashboardTrendMetricCurrent,
            child: MoneyText(
              amount: last.toDouble(),
              currencyCode: currency,
              compact: true,
              style: TypographyTokens.numericTitleStrong,
            ),
          ),
        ),
        Container(
          width: AppSpacing.hairline,
          height: AppSpacing.s48,
          color: colors.border.withValues(alpha: AppOpacity.highlight),
        ),
        const SizedBox(width: AppSpacing.s16),
        Expanded(
          child: _TrendMetricValue(
            label: l10n.dashboardTrendMetricChange,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
