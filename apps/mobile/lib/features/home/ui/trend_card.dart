import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../core/ai/intent/intent.dart';
import '../../../core/format/formatters.dart';
import '../../../core/format/providers.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../ai_chat/ui/ai_hover_overlay.dart';
import '../../ai_chat/ui/ai_object_capsule.dart';
import '../data/dashboard_providers.dart';
import '../domain/dashboard_time_range.dart';
import '../domain/dashboard_trend_builder.dart';
import 'dashboard_chart_fullscreen.dart';
import 'home_section.dart';

/// Net-worth trend card: time-range chips + line chart.
///
/// The chart and chips watch [dashboardTrendProvider] / the selection
/// providers directly so the UI has no internal state to keep in sync.
class TrendCard extends ConsumerWidget {
  const TrendCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final trendAsync = ref.watch(dashboardTrendProvider);

    // §5.10 Layer 2 — advertise this card's identity/timeframe so any
    // AI surface fired from inside the card gets the right context.
    final selectedRange = ref.watch(dashboardTimeRangeProvider);
    return AiContextChipScope(
      chips: <AiContextChip>[
        AiContextChip(
          key: 'chart',
          label: l10n.dashboardTrendTitle,
          value: 'net_worth_trend',
        ),
        AiContextChip(
          key: 'timeframe',
          label: selectedRange.preset.name,
          value: selectedRange.preset.name,
        ),
      ],
      child: AiHoverOverlay(
        capsule: trendAsync.maybeWhen(
          data: (trend) => trend.isEmpty
              ? const SizedBox.shrink()
              : AiObjectCapsule(
                  source: 'home_trend_card',
                  intent: 'explain_chart',
                  object: const AiObjectRef(
                    type: 'chart',
                    id: 'net_worth_trend',
                  ),
                  objectLabel: l10n.dashboardTrendTitle,
                ),
          orElse: () => const SizedBox.shrink(),
        ),
        child: HomeSurface(
          padding: const EdgeInsets.all(AppSpacing.s16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              HomeCardHeader(
                title: l10n.dashboardTrendTitle,
                trailing: trendAsync.maybeWhen(
                  data: (trend) => FTooltip(
                    tipBuilder: (_, _) => Text(l10n.aiChatSheetExpandTooltip),
                    child: FButton.icon(
                      variant: FButtonVariant.ghost,
                      onPress: trend.isEmpty
                          ? null
                          : () => showDashboardChartFullscreen(
                              context: context,
                              title: l10n.dashboardTrendTitle,
                              child: const _TrendFullscreenContent(),
                            ),
                      child: const Icon(
                        FLucideIcons.maximize,
                        size: AppIconSizes.md,
                      ),
                    ),
                  ),
                  orElse: () => const SizedBox(
                    width: AppSpacing.s48,
                    height: AppSpacing.s48,
                  ),
                ),
              ),
              trendAsync.maybeWhen(
                data: (trend) => trend.isEmpty
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.s6),
                        child: _TrendSummary(trend: trend),
                      ),
                orElse: () => const SizedBox.shrink(),
              ),
              const SizedBox(height: AppSpacing.s12),
              const _RangeChips(),
              const SizedBox(height: AppSpacing.s12),
              trendAsync.when(
                loading: () => const _TrendSkeleton(),
                error: (e, st) => _TrendError(error: e),
                data: (trend) => _TrendChart(trend: trend, showSummary: false),
              ),
            ],
          ),
        ),
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
        const SizedBox(height: AppSpacing.s16),
        Expanded(
          child: trendAsync.when(
            loading: () => const _TrendSkeleton(),
            error: (e, st) => _TrendError(error: e),
            data: (trend) => _TrendChart(
              trend: trend,
              fillAvailableHeight: true,
              showSummary: false,
              showYAxis: true,
            ),
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
    return SegmentedRow<DashboardRangePreset>(
      options: DashboardRangePreset.values,
      value: selected,
      labelOf: (preset) => _rangeLabel(l10n, preset),
      onChanged: (preset) => _select(context, ref, preset),
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
  const _TrendChart({
    required this.trend,
    this.fillAvailableHeight = false,
    this.showSummary = true,
    this.showYAxis = false,
  });

  final DashboardTrend trend;
  final bool fillAvailableHeight;
  final bool showSummary;
  final bool showYAxis;

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

        // Flat series (e.g. brand-new account, no history yet) carries no
        // analytical signal. Drawing a full chart for it produced a
        // misleading ±¥1 axis, a dotted line and a heavy gradient block
        // that collided with the caption. Instead show a calm, centered
        // baseline: endpoints only, no axis numbers, no fill — it reads
        // as "steady / awaiting data" and morphs into the real chart the
        // moment values start moving.
        if (allFlat) {
          final flat = trend.points;
          final flatSeries = ChartSeries(
            name: 'netWorth',
            points: [
              ChartPoint(
                x: flat.first.asOf.millisecondsSinceEpoch.toDouble(),
                y: flat.first.netWorth.amount.toDouble(),
                meta: flat.first,
              ),
              ChartPoint(
                x: flat.last.asOf.millisecondsSinceEpoch.toDouble(),
                y: flat.last.netWorth.amount.toDouble(),
                meta: flat.last,
              ),
            ],
          );
          final flatChart = NwLineChart(
            series: [flatSeries],
            minimal: true,
            interpolation: ChartInterpolation.linear,
            semanticLabel: AppLocalizations.of(context).dashboardTrendTitle,
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (fillAvailableHeight)
                Expanded(child: flatChart)
              else
                SizedBox(height: AppChartHeights.mini, child: flatChart),
              const SizedBox(height: AppSpacing.s12),
              Text(
                AppLocalizations.of(context).dashboardTrendFlatHint,
                style: context.captionStyle.copyWith(height: 1.4),
              ),
            ],
          );
        }

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
          showYAxis: showYAxis,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showSummary) ...[
              _TrendSummary(trend: trend),
              const SizedBox(height: AppSpacing.s16),
            ],
            if (fillAvailableHeight)
              Expanded(child: chart)
            else
              SizedBox(height: AppChartHeights.full, child: chart),
          ],
        );
      },
    );
  }
}

class _TrendSummary extends ConsumerWidget {
  const _TrendSummary({required this.trend});

  final DashboardTrend trend;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (trend.points.length < 2) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context);
    final formatters = context.formatters(ref);
    final first = trend.points.first;
    final last = trend.points.last;
    final delta = last.netWorth.amount - first.netWorth.amount;
    final firstValue = first.netWorth.amount.toDouble();
    final ratio = firstValue.abs() <= 0
        ? null
        : delta.toDouble() / firstValue.abs();
    final hidden = AmountPrivacyScope.isHiddenOf(context);
    final current = hidden
        ? AmountPrivacyScope.mask
        : formatters.compactCurrency(
            last.netWorth.amount,
            code: trend.baseCurrency,
          );
    final rangeLabel = _formatDateRange(
      formatters,
      first.asOf.toLocal(),
      last.asOf.toLocal(),
    );
    final colors = context.theme.colors;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.dashboardTrendMetricCurrent,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.microCaptionStyle.copyWith(
                  color: colors.mutedForeground,
                ),
              ),
              const SizedBox(height: AppSpacing.s2),
              Text(
                current,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TypographyTokens.numericTitleStrong.copyWith(
                  color: colors.foreground,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.s16),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Wrap(
                alignment: WrapAlignment.end,
                spacing: AppSpacing.s6,
                runSpacing: AppSpacing.s2,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  DeltaText(
                    value: delta.toDouble(),
                    format: DeltaFormat.currency,
                    currencyCode: trend.baseCurrency,
                    fractionDigits: 0,
                    showIcon: false,
                    style: TypographyTokens.numericBodyStrong,
                  ),
                  if (ratio != null)
                    Text(
                      formatters.signedPercent(ratio, decimalDigits: 1),
                      style: context.captionMediumStyle.copyWith(
                        color: colors.mutedForeground,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.s2),
              Text(
                rangeLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: context.microCaptionStyle.copyWith(
                  color: colors.mutedForeground,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatDateRange(
    AppFormatters formatters,
    DateTime start,
    DateTime end,
  ) {
    final sameYear = start.year == end.year;
    final startLabel = sameYear
        ? formatters.monthDay(start)
        : formatters.date(start);
    final endLabel = sameYear ? formatters.monthDay(end) : formatters.date(end);
    return '$startLabel - $endLabel';
  }
}

class _LineChartBody extends StatelessWidget {
  const _LineChartBody({
    required this.series,
    required this.trend,
    required this.dateFmt,
    required this.showYAxis,
  });

  final ChartSeries series;
  final DashboardTrend trend;
  final AxisDateFormat dateFmt;
  final bool showYAxis;

  @override
  Widget build(BuildContext context) {
    final delta =
        trend.points.last.netWorth.amount - trend.points.first.netWorth.amount;
    final intent = delta.sign > 0
        ? SeriesIntent.up
        : delta.sign < 0
        ? SeriesIntent.down
        : SeriesIntent.primary;
    final chartSeries = ChartSeries(
      name: AppLocalizations.of(context).dashboardTrendTitle,
      points: series.points,
      intent: intent,
      fillOpacity: 0.16,
      strokeWidth: AppStroke.accent,
    );
    return NwLineChart(
      series: [chartSeries],
      xAxis: TimeAxis(format: dateFmt, maxLabels: 4),
      yAxis: ValueAxis.currency(
        currencyCode: trend.baseCurrency,
        maxLabels: 3,
        showGrid: true,
      ),
      filled: true,
      interpolation: ChartInterpolation.linear,
      heroDots: true,
      showXAxis: true,
      showYAxis: showYAxis,
      showTouchXAxisLabel: true,
      semanticLabel: AppLocalizations.of(context).dashboardTrendTitle,
    );
  }
}

class _TrendSkeleton extends StatelessWidget {
  const _TrendSkeleton();

  @override
  Widget build(BuildContext context) {
    return const SkeletonBox(height: 220, radius: 8);
  }
}

class _TrendError extends StatelessWidget {
  const _TrendError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s24),
      child: Center(
        child: Text(
          l10n.dashboardTrendError('$error'),
          style: context.captionStyle.copyWith(
            color: context.theme.colors.destructive,
          ),
        ),
      ),
    );
  }
}
