import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/features/finance/fire/data/fire_providers.dart';
import 'package:naviwealth/features/finance/fire/domain/fire_projection.dart';

import '../../../core/shell/shell_chrome.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
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
      child: AdaptiveContentFrame(
        maxWidth: AdaptiveMaxWidth.dashboard,
        expandSinglePrimary: true,
        primary: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(fireDashboardViewProvider);
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              AppSpacing.s16,
              AppSpacing.s8,
              AppSpacing.s16,
              kTabBarOffset + MediaQuery.paddingOf(context).bottom,
            ),
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
class _PlanNextSteps extends StatelessWidget {
  const _PlanNextSteps();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final steps = <_PlanTileSpec>[
      _PlanTileSpec(
        icon: FLucideIcons.scale,
        title: l10n.planRebalanceSectionTitle,
        path: FinanceRoutes.planRebalance,
      ),
      _PlanTileSpec(
        icon: FLucideIcons.piggyBank,
        title: l10n.planBudgetSectionTitle,
        path: FinanceRoutes.planBudget,
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.planCoreSectionTitle, style: context.mutedLabelStyle),
        const SizedBox(height: AppSpacing.s10),
        Row(
          children: [
            for (var i = 0; i < steps.length; i++) ...[
              if (i > 0) const SizedBox(width: AppSpacing.s10),
              Expanded(child: _PlanTile(spec: steps[i])),
            ],
          ],
        ),
      ],
    );
  }
}

class _PlanMoreTools extends StatefulWidget {
  const _PlanMoreTools();

  @override
  State<_PlanMoreTools> createState() => _PlanMoreToolsState();
}

class _PlanMoreToolsState extends State<_PlanMoreTools> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;
    final tools = <_PlanTileSpec>[
      _PlanTileSpec(
        icon: FLucideIcons.calendarClock,
        title: l10n.planDcaSectionTitle,
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
        path: FinanceRoutes.planWheel,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SoftCard.raised(
          borderless: true,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s14,
            vertical: AppSpacing.s12,
          ),
          onPress: () {
            AppInteraction.signal(AppInteractionIntent.reveal);
            setState(() => _open = !_open);
          },
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l10n.planStrategyToolsSectionTitle,
                  style: context.rowTitleStyle,
                ),
              ),
              Icon(
                _open ? FLucideIcons.chevronUp : FLucideIcons.chevronDown,
                size: AppIconSizes.md,
                color: colors.mutedForeground,
              ),
            ],
          ),
        ),
        AnimatedSizeFade(
          visible: _open,
          child: Padding(
            padding: const EdgeInsets.only(top: AppSpacing.s10),
            child: Wrap(
              spacing: AppSpacing.s10,
              runSpacing: AppSpacing.s10,
              children: [
                for (final spec in tools)
                  SizedBox(
                    width:
                        (MediaQuery.sizeOf(context).width -
                            AppSpacing.s16 * 2 -
                            AppSpacing.s10) /
                        2,
                    child: _PlanTile(spec: spec),
                  ),
              ],
            ),
          ),
        ),
      ],
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
            child: Text(
              spec.title,
              style: context.labelStyle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
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
  });

  final IconData icon;
  final String title;
  final String path;
}
