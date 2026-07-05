import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/ai/intent/intent.dart';
import 'package:naviwealth/core/ai/visual/ai_hover_overlay.dart';
import 'package:naviwealth/core/ai/visual/ai_object_capsule.dart';
import 'package:naviwealth/core/format/formatters.dart';
import 'package:naviwealth/core/format/providers.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/application/read_models/dashboard_providers.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../domain/dashboard_time_range.dart';
import '../domain/dashboard_trend_builder.dart';
import 'dashboard_chart_fullscreen.dart';
import 'home_section.dart';

part 'trend_card_chart.dart';
part 'trend_card_range.dart';
part 'trend_card_states.dart';
part 'trend_card_summary.dart';

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
