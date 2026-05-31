import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../core/ai/intent/intent.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../ai_chat/ui/ai_hover_overlay.dart';
import '../../ai_chat/ui/ai_object_capsule.dart';
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
        child: SoftCard(
          padding: const EdgeInsets.all(AppSpacing.s20),
          borderRadius: 18,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.dashboardTrendTitle,
                      style: context.theme.typography.md,
                    ),
                  ),
                  trendAsync.maybeWhen(
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
                        child: const Icon(FLucideIcons.maximize, size: AppIconSizes.md),
                      ),
                    ),
                    orElse: () => const SizedBox(width: AppSpacing.s48, height: AppSpacing.s48),
                  ),
                ],
              ),
              const _RangeChips(),
              const SizedBox(height: AppSpacing.s12),
              trendAsync.when(
                loading: () => const _TrendSkeleton(),
                error: (e, st) => _TrendError(error: e),
                data: (trend) => _TrendChart(trend: trend),
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
    final colors = context.theme.colors;
    return SizedBox(
      height: 30,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final preset in DashboardRangePreset.values)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.s4),
              child: _RangeChip(
                label: _rangeLabel(l10n, preset),
                selected: preset == selected,
                onTap: () => _select(context, ref, preset),
                colors: colors,
                typography: context.theme.typography,
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

/// Apple Stocks / TradingView-mobile style timeframe chip — pill, no
/// border, low-contrast hover state, accent fill only when selected.
/// Lighter than [FButton] outlined variant so the chart breathes.
class _RangeChip extends StatelessWidget {
  const _RangeChip({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.colors,
    required this.typography,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final FColors colors;
  final FTypography typography;

  @override
  Widget build(BuildContext context) {
    final bg = selected
        ? colors.primary.withValues(alpha: AppOpacity.medium)
        : Colors.transparent;
    final fg = selected ? colors.primary : colors.mutedForeground;
    return FTappable(
      onPress: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s10, vertical: AppSpacing.s4),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppRadius.xs),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: typography.xs.copyWith(
            color: fg,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
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
                SizedBox(height: 132, child: flatChart),
              const SizedBox(height: AppSpacing.s12),
              Text(
                AppLocalizations.of(context).dashboardTrendFlatHint,
                style: context.theme.typography.xs.copyWith(
                  color: context.theme.colors.mutedForeground,
                  height: 1.4,
                ),
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
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (fillAvailableHeight)
              Expanded(child: chart)
            else
              SizedBox(height: 220, child: chart),
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
      yAxis: ValueAxis.currency(currencyCode: trend.baseCurrency, maxLabels: 3),
      filled: true,
      interpolation: ChartInterpolation.linear,
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
          style: context.theme.typography.xs.copyWith(
            color: context.theme.colors.destructive,
          ),
        ),
      ),
    );
  }
}
