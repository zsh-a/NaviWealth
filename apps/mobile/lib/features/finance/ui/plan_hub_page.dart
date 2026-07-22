import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/features/finance/fire/data/fire_providers.dart';
import 'package:naviwealth/features/finance/fire/domain/fire_projection.dart';

import '../../../core/shell/shell_chrome.dart';
import '../../../core/shell/shell_visibility.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../application/planning_hub_status.dart';
import '../composition/finance_route_paths.dart';

/// Plan hub — one decision story (FIRE) plus a short list of next steps.
///
/// Strategy simulators stay behind a single collapsible “more tools”
/// control so the landing surface is not a tool directory.
class PlanHubPage extends ConsumerWidget {
  const PlanHubPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return ShellTabScaffold(
      title: l10n.planHubTitle,
      childPad: false,
      child: ShellTabPause(
        routePath: FinanceRoutes.plan,
        placeholder: const SizedBox.expand(),
        child: AdaptiveContentFrame(
          maxWidth: AdaptiveMaxWidth.dashboard,
          expandSinglePrimary: true,
          // ListView owns content + shell bottom inset; avoid double padding
          // from AdaptiveContentFrame's default MediaQuery bottom pad.
          padding: EdgeInsets.zero,
          primary: RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(fireDashboardViewProvider);
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: shellTabContentPadding(context, top: AppSpacing.s8),
              children: const [
                _FireSummaryCard(),
                SizedBox(height: AppSpacing.s20),
                _PlanNextSteps(),
                SizedBox(height: AppSpacing.s16),
                _PlanMoreTools(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FireSummaryCard extends ConsumerWidget {
  const _FireSummaryCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final viewAsync = ref.watch(fireDashboardViewProvider);

    return viewAsync.when(
      loading: () => SoftCard.hero(
        padding: AppPageRhythm.heroPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.planFireSectionTitle, style: context.mutedLabelStyle),
            const SizedBox(height: AppSpacing.s8),
            const SkeletonBox(width: 220, height: 34, radius: AppRadius.sm),
            const SizedBox(height: AppSpacing.s16),
            const SkeletonBox(height: 10, radius: AppRadius.full),
          ],
        ),
      ),
      error: (error, _) => _errorHero(context, ref, l10n, error),
      data: (view) {
        final progress = view.progressRatio;
        if (progress == null) {
          return _emptyHero(context, l10n);
        }
        final liveScenario = view.scenarios.firstWhereOrNull(
          (s) => s.tier == FireScenarioTier.live,
        );
        final neutralScenario = view.scenarios.firstWhereOrNull(
          (s) => s.tier == FireScenarioTier.neutral,
        );
        final scenario =
            liveScenario ?? neutralScenario ?? view.scenarios.firstOrNull;
        return _card(
          context: context,
          l10n: l10n,
          progress: progress,
          monthsToTarget: scenario?.monthsToTarget,
        );
      },
    );
  }

  Widget _emptyHero(BuildContext context, AppLocalizations l10n) {
    return SoftCard.hero(
      onPress: () => context.push(FinanceRoutes.planFire),
      padding: AppPageRhythm.heroPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.planFireSectionTitle, style: context.mutedLabelStyle),
          const SizedBox(height: AppSpacing.s8),
          Text(l10n.planHeroEmpty, style: context.rowTitleStyle),
          const SizedBox(height: AppSpacing.s14),
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.planHeroConfigure,
                  style: context.captionLabelStyle.copyWith(
                    color: context.theme.colors.primary,
                  ),
                ),
              ),
              Icon(
                FLucideIcons.chevronRight,
                size: AppIconSizes.sm,
                color: context.theme.colors.primary,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _errorHero(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    Object error,
  ) {
    return SoftCard.raised(
      padding: EdgeInsets.zero,
      borderRadius: AppRadius.lg,
      borderless: true,
      tinted: false,
      child: AppEmptyState.error(
        title: l10n.commonLoadFailed,
        message: userSafeErrorMessage(context, error),
        retryLabel: l10n.commonRetry,
        onRetry: () => ref.invalidate(fireDashboardViewProvider),
      ),
    );
  }

  Widget _card({
    required BuildContext context,
    required AppLocalizations l10n,
    required double progress,
    required int? monthsToTarget,
  }) {
    final years = monthsToTarget == null
        ? null
        : (monthsToTarget / 12).toStringAsFixed(monthsToTarget < 24 ? 1 : 0);
    final progressPct = (progress * 100).clamp(0, 100).toStringAsFixed(0);
    return SoftCard.hero(
      onPress: () => context.push(FinanceRoutes.planFire),
      padding: AppPageRhythm.heroPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.planFireSectionTitle, style: context.mutedLabelStyle),
          const SizedBox(height: AppSpacing.s10),
          if (years != null)
            Text(
              l10n.planHeroYearsToFire(years),
              style: TypographyTokens.displayLarge,
            )
          else
            Text(
              '${l10n.planHeroProgressLabel} $progressPct%',
              style: TypographyTokens.displayLarge,
            ),
          const SizedBox(height: AppPageRhythm.module),
          FDeterminateProgress(value: progress),
          const SizedBox(height: AppSpacing.s8),
          Text(
            '${l10n.planHeroProgressLabel} $progressPct%',
            style: context.captionStyle,
          ),
          const SizedBox(height: AppSpacing.s14),
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.planHeroSeePlan,
                  style: context.captionLabelStyle.copyWith(
                    color: context.theme.colors.primary,
                  ),
                ),
              ),
              Icon(
                FLucideIcons.chevronRight,
                size: AppIconSizes.sm,
                color: context.theme.colors.primary,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// High-frequency planning steps as a compact 2-up tile row.
class _PlanNextSteps extends ConsumerWidget {
  const _PlanNextSteps();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final status = ref.watch(planningHubStatusProvider);
    final steps = <_PlanTileSpec>[
      _PlanTileSpec(
        icon: FLucideIcons.calendarRange,
        title: l10n.moneyRunwayTitle,
        subtitle: _runwayStatusLabel(l10n, status.runway),
        path: FinanceRoutes.planRunway,
      ),
      _PlanTileSpec(
        icon: FLucideIcons.waypoints,
        title: l10n.lifeEventScenariosTitle,
        subtitle: status.pendingLifeEventReviews == null
            ? null
            : status.pendingLifeEventReviews == 0
            ? l10n.planStatusNoPendingReviews
            : l10n.planStatusPendingReviews(status.pendingLifeEventReviews!),
        path: FinanceRoutes.planLifeEvents,
      ),
      _PlanTileSpec(
        icon: FLucideIcons.scale,
        title: l10n.planRebalanceSectionTitle,
        subtitle: _rebalanceStatusLabel(l10n, status),
        path: FinanceRoutes.planRebalance,
      ),
      _PlanTileSpec(
        icon: FLucideIcons.piggyBank,
        title: l10n.planBudgetSectionTitle,
        subtitle: status.budgetCount == null
            ? null
            : status.budgetCount == 0
            ? l10n.planStatusNeedsSetup
            : l10n.planStatusBudgetCount(status.budgetCount!),
        path: FinanceRoutes.planBudget,
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.planCoreSectionTitle, style: context.mutedLabelStyle),
        const SizedBox(height: AppSpacing.s10),
        _PlanTileGrid(tiles: steps),
      ],
    );
  }
}

class _PlanMoreTools extends ConsumerStatefulWidget {
  const _PlanMoreTools();

  @override
  ConsumerState<_PlanMoreTools> createState() => _PlanMoreToolsState();
}

class _PlanMoreToolsState extends ConsumerState<_PlanMoreTools> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final status = ref.watch(planningHubStatusProvider);
    final tools = <_PlanTileSpec>[
      _PlanTileSpec(
        icon: FLucideIcons.calendarClock,
        title: l10n.planDcaSectionTitle,
        subtitle: _dcaStatusLabel(context, l10n, status),
        path: FinanceRoutes.planDca,
      ),
      if (!kIsWeb)
        _PlanTileSpec(
          icon: FLucideIcons.candlestickChart,
          title: l10n.planIncomeSectionTitle,
          path: FinanceRoutes.planIncome,
        ),
      _PlanTileSpec(
        icon: FLucideIcons.refreshCw,
        title: l10n.planWheelSectionTitle,
        subtitle: status.wheelCycleCount == null
            ? null
            : status.wheelCycleCount == 0
            ? l10n.planStatusNeedsSetup
            : status.wheelOpenPositionCount! > 0
            ? l10n.planStatusWheelOpen(status.wheelOpenPositionCount!)
            : l10n.planStatusWheelCycles(status.wheelCycleCount!),
        path: FinanceRoutes.planWheel,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppDisclosureHeader(
          title: l10n.planStrategyToolsSectionTitle,
          expanded: _open,
          onToggle: () => setState(() => _open = !_open),
        ),
        AnimatedSizeFade(
          visible: _open,
          child: Padding(
            padding: const EdgeInsets.only(top: AppSpacing.s10),
            child: _PlanTileGrid(tiles: tools, maxColumns: 3),
          ),
        ),
      ],
    );
  }
}

class _PlanTileGrid extends StatelessWidget {
  const _PlanTileGrid({required this.tiles, this.maxColumns = 2});

  final List<_PlanTileSpec> tiles;
  final int maxColumns;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = AppSpacing.s10;
        // Compact action tiles remain legible at two-up phone widths because
        // labels wrap to two lines. This also keeps the disclosure section in
        // the initial lazy-list build range at large accessibility text sizes.
        const minTileWidth = 136.0;
        final fittingColumns =
            ((constraints.maxWidth + gap) / (minTileWidth + gap)).floor();
        final columns = fittingColumns.clamp(1, maxColumns);
        final tileWidth =
            (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final tile in tiles)
              SizedBox(
                width: tileWidth,
                child: _PlanTile(spec: tile),
              ),
          ],
        );
      },
    );
  }
}

class _PlanTile extends StatelessWidget {
  const _PlanTile({required this.spec});

  final _PlanTileSpec spec;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return SoftCard.raised(
      borderless: true,
      onPress: () => context.push(spec.path),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s12,
        vertical: AppSpacing.s14,
      ),
      child: Row(
        children: [
          Icon(spec.icon, size: AppIconSizes.md, color: colors.primary),
          const SizedBox(width: AppSpacing.s10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  spec.title,
                  style: context.labelStyle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (spec.subtitle != null) ...[
                  const SizedBox(height: AppSpacing.s2),
                  Text(
                    spec.subtitle!,
                    style: context.captionStyle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanTileSpec {
  const _PlanTileSpec({
    required this.icon,
    required this.title,
    required this.path,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String path;
  final String? subtitle;
}

String? _runwayStatusLabel(
  AppLocalizations l10n,
  PlanningRunwayStatus? status,
) => switch (status) {
  null => null,
  PlanningRunwayStatus.needsData => l10n.planStatusNeedsSetup,
  PlanningRunwayStatus.healthy => l10n.moneyRunwayStatusHealthy,
  PlanningRunwayStatus.watch => l10n.moneyRunwayStatusWatch,
  PlanningRunwayStatus.shortfall => l10n.moneyRunwayStatusShortfall,
};

String? _rebalanceStatusLabel(
  AppLocalizations l10n,
  PlanningHubStatus status,
) => switch (status.rebalance) {
  null => null,
  PlanningRebalanceStatus.needsData => l10n.planStatusNeedsSetup,
  PlanningRebalanceStatus.balanced => l10n.planStatusRebalanceBalanced,
  PlanningRebalanceStatus.attention => l10n.planStatusRebalanceAttention(
    ((status.rebalanceDriftPct ?? 0) * 100).toStringAsFixed(1),
  ),
  PlanningRebalanceStatus.active => l10n.planStatusRebalanceActive,
};

String? _dcaStatusLabel(
  BuildContext context,
  AppLocalizations l10n,
  PlanningHubStatus status,
) {
  if (status.dcaPlanCount == null) return null;
  if (status.dcaPlanCount == 0) return l10n.planStatusNeedsSetup;
  final nextDue = status.dcaNextDueAt;
  if (nextDue == null) return l10n.planStatusDcaPaused;
  if (status.dcaDue) return l10n.planStatusDcaDue;
  final date = MaterialLocalizations.of(
    context,
  ).formatShortDate(nextDue.toLocal());
  return l10n.planStatusDcaNext(date);
}
