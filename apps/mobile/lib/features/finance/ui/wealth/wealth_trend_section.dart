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
class WealthTrendSection extends ConsumerWidget {
  const WealthTrendSection({super.key, this.overviewBuilder});

  /// Integrates the balance summary with its chart on the page canvas. The
  /// chart owns scrub state so changing ranges, loading, or retrying restores
  /// the current balance without leaving a stale historical readout behind.
  final Widget Function(BuildContext context, NwScrubState? scrub)?
  overviewBuilder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final range = ref.watch(dashboardTimeRangeProvider);
    final trendAsync = ref.watch(dashboardTrendProvider(range));
    final baseCurrency = ref.watch(dashboardBaseCurrencyProvider);

    final overview = overviewBuilder;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (overview == null)
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
        if (overview == null) const SizedBox(height: AppSpacing.s12),
        // Keep changing chart nodes separate from the focused range control.
        Semantics(
          container: true,
          child: ContentCrossFade(
            child: KeyedSubtree(
              key: ValueKey('wealth-trend-${range.preset.name}'),
              child: trendAsync.when(
                loading: () => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (overview != null) overview(context, null),
                    if (overview != null)
                      const SizedBox(height: AppSpacing.s16),
                    _WealthTrendSkeleton(integrated: overview != null),
                  ],
                ),
                error: (_, _) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (overview != null) overview(context, null),
                    _WealthTrendError(
                      onRetry: () =>
                          ref.invalidate(dashboardTrendProvider(range)),
                    ),
                  ],
                ),
                data: (trend) =>
                    _WealthTrendBody(trend: trend, overviewBuilder: overview),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.s12),
        const _WealthTrendRangeSelector(),
      ],
    );
    return overview != null
        ? KeyedSubtree(
            key: const ValueKey('wealth-trend-section'),
            child: content,
          )
        : SoftCard.flat(
            key: const ValueKey('wealth-trend-section'),
            padding: AppPageRhythm.cardPadding,
            child: content,
          );
  }
}

class _WealthTrendBody extends StatefulWidget {
  const _WealthTrendBody({required this.trend, this.overviewBuilder});

  final DashboardTrend trend;
  final Widget Function(BuildContext context, NwScrubState? scrub)?
  overviewBuilder;

  @override
  State<_WealthTrendBody> createState() => _WealthTrendBodyState();
}

class _WealthTrendBodyState extends State<_WealthTrendBody> {
  // Live scrub sample — drives the header readout (Robinhood/Copilot
  // pattern: the value/date move to the header while the chart keeps only
  // the crosshair). `null` restores the resting latest-value state.
  NwScrubState? _scrub;

  @override
  void didUpdateWidget(covariant _WealthTrendBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.trend != widget.trend) _scrub = null;
  }

  @override
  Widget build(BuildContext context) {
    final trend = widget.trend;
    final l10n = AppLocalizations.of(context);
    final segments = trend.chartableSegments;
    if (segments.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.overviewBuilder case final overview?)
            overview(context, null),
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
    final values = [for (final p in summaryPoints) p.netWorth.amount];
    final allFlat = values.every((value) => value == values.first);

    final seriesName = l10n.homeNetWorthTitle;
    final series = <ChartSeries>[
      for (final segment in segments)
        ChartSeries(
          name: seriesName,
          points: [
            for (final point in segment.points)
              ChartPoint(
                x: point.asOf.millisecondsSinceEpoch.toDouble(),
                y: point.netWorth.amount.toDouble(),
                meta: point,
              ),
          ],
          intent: SeriesIntent.primary,
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

    final xAxis = TimeAxis(
      format: _dateFormatFor(trend.range),
      locale: Localizations.localeOf(context).toLanguageTag(),
      maxLabels: 4,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.overviewBuilder case final overview?) ...[
          overview(context, _scrub),
          const SizedBox(height: AppSpacing.s16),
        ],
        _WealthTrendSummary(
          currency: trend.baseCurrency,
          baseline: !estimatedOnly && values.length > 1 ? values.first : null,
          current: values.last,
          scrub: _scrub,
          formatScrubDate: xAxis.formatPrecise,
          showCurrentValue: widget.overviewBuilder == null,
        ),
        const SizedBox(height: AppSpacing.s16),
        SizedBox(
          key: const ValueKey('wealth-trend-chart'),
          height: AppChartHeights.compact,
          child: NwLineChart(
            series: series,
            // Tight fit around real data so short histories fill the plot.
            minX: dataMinX,
            maxX: dataMaxX <= dataMinX ? null : dataMaxX,
            xAxis: xAxis,
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
            onScrubChanged: (state) => setState(() => _scrub = state),
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
    required this.scrub,
    required this.formatScrubDate,
    this.showCurrentValue = true,
  });

  final String currency;
  final Decimal? baseline;
  final Decimal current;

  /// Live scrub sample from the trend chart — while scrubbing, the header
  /// shows the scrubbed value and its date instead of the resting readout.
  final NwScrubState? scrub;

  /// Formats a scrubbed point's X coordinate (ms since epoch) for display.
  final String Function(double x) formatScrubDate;
  final bool showCurrentValue;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final delta = baseline == null ? null : current - baseline!;
    final baselineDouble = baseline?.toDouble();
    final ratio = baselineDouble == null || baselineDouble.abs() <= 0
        ? null
        : delta!.toDouble() / baselineDouble.abs();
    final hidden = AmountPrivacyScope.isHiddenOf(context);
    final scrub = this.scrub;

    if (!showCurrentValue) {
      return Wrap(
        spacing: AppSpacing.s8,
        runSpacing: AppSpacing.s4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(l10n.dashboardTrendMetricChange, style: context.captionStyle),
          if (delta == null)
            Text('—', style: context.appTheme.type.numericBody)
          else
            DeltaText(
              value: delta.toDouble(),
              format: DeltaFormat.currency,
              currencyCode: currency,
              fractionDigits: 0,
              style: context.appTheme.type.numericBodyStrong,
            ),
          if (ratio != null && !hidden)
            DeltaText.percentFromRatio(
              ratio: ratio,
              fractionDigits: 1,
              showIcon: false,
              style: context.captionStyle,
            ),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                scrub != null
                    ? formatScrubDate(scrub.point.x)
                    : l10n.dashboardTrendMetricChange,
                style: context.microCaptionStyle,
              ),
              const SizedBox(height: AppSpacing.s2),
              // Scrubbed value while dragging, latest value at rest. Plain
              // MoneyText (no count-up) so the readout tracks the finger
              // 1:1; tabular figures come from the global type tokens.
              MoneyText(
                key: const ValueKey('wealth-trend-scrub-value'),
                amount: scrub?.point.y ?? current.toDouble(),
                currencyCode: currency,
                fractionDigits: 0,
                style: context.appTheme.type.numericTitleStrong,
                color: context.theme.colors.foreground,
              ),
            ],
          ),
        ),
        if (delta == null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.s16),
            child: Text('—', style: context.appTheme.type.numericBodyStrong),
          )
        else ...[
          const SizedBox(width: AppSpacing.s8),
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.s16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                DeltaText(
                  value: delta.toDouble(),
                  format: DeltaFormat.currency,
                  currencyCode: currency,
                  fractionDigits: 0,
                  showIcon: false,
                  style: context.appTheme.type.numericBodyStrong,
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
        ],
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
    String labelOf(DashboardRangePreset range) => switch (range) {
      DashboardRangePreset.m1 => l10n.dashboardRange1M,
      DashboardRangePreset.m3 => l10n.dashboardRange3M,
      DashboardRangePreset.y1 => l10n.dashboardRange1Y,
      DashboardRangePreset.y3 => l10n.dashboardRange3Y,
      DashboardRangePreset.all => l10n.dashboardRangeAll,
      DashboardRangePreset.m6 => l10n.dashboardRange6M,
      DashboardRangePreset.custom => l10n.dashboardRangeCustom,
    };
    return SegmentedRow<DashboardRangePreset>.inline(
      options: _ranges,
      value: selected,
      labelOf: labelOf,
      semanticLabelOf: (range) => '${l10n.wealthTrendTitle}: ${labelOf(range)}',
      minSegmentWidth: AppSpacing.s48,
      onChanged: (range) {
        ref.read(dashboardCustomRangeProvider.notifier).state = null;
        ref.read(dashboardSelectedRangeProvider.notifier).state = range;
      },
    );
  }
}

class _WealthTrendSkeleton extends StatelessWidget {
  const _WealthTrendSkeleton({this.integrated = false});

  final bool integrated;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (integrated)
          const Align(
            alignment: AlignmentDirectional.centerStart,
            child: SkeletonBox(width: 160, height: 18),
          )
        else
          const Row(
            children: [
              Expanded(child: SkeletonBox(height: AppSpacing.s48)),
              SizedBox(width: AppSpacing.s16),
              Expanded(child: SkeletonBox(height: AppSpacing.s48)),
            ],
          ),
        const SizedBox(height: AppSpacing.s16),
        const SkeletonBox(height: AppChartHeights.compact),
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
            AppQuietButton(label: l10n.commonRetry, onPress: onRetry),
          ],
        ),
      ),
    );
  }
}
