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

/// Plan hub — landing page for FinanceOS planning.
///
/// The hub stays focused on decisions that change the future state: FIRE,
/// allocation/rebalance, and strategy tools. Read-only analytics and
/// half-wired placeholders deliberately stay out of this surface.
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
            padding: EdgeInsets.only(
              bottom: kTabBarOffset + MediaQuery.paddingOf(context).bottom,
            ),
            children: const [
              _FireSummaryCard(),
              SizedBox(height: AppSpacing.s20),
              _PlanActions(),
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

class _PlanActions extends StatelessWidget {
  const _PlanActions();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final nextSteps = _PlanActionSection(
      title: l10n.planCoreSectionTitle,
      subtitle: l10n.planCoreSectionSubtitle,
      actions: [
        _PlanActionSpec(
          icon: FLucideIcons.piggyBank,
          title: l10n.planBudgetSectionTitle,
          subtitle: l10n.planBudgetSectionSubtitle,
          path: FinanceRoutes.planBudget,
        ),
        _PlanActionSpec(
          icon: FLucideIcons.scale,
          title: l10n.planRebalanceSectionTitle,
          subtitle: l10n.planRebalanceSectionSubtitle,
          path: FinanceRoutes.planRebalance,
        ),
        _PlanActionSpec(
          icon: FLucideIcons.calendarClock,
          title: l10n.planDcaSectionTitle,
          subtitle: l10n.planDcaSectionSubtitle,
          path: FinanceRoutes.planDca,
        ),
      ],
    );
    final strategies = _PlanActionSection(
      title: l10n.planStrategyToolsSectionTitle,
      subtitle: l10n.planStrategyToolsSectionSubtitle,
      actions: [
        if (!kIsWeb)
          _PlanActionSpec(
            icon: FLucideIcons.candlestickChart,
            title: l10n.planIncomeSectionTitle,
            subtitle: l10n.planIncomeSectionSubtitle,
            path: FinanceRoutes.planIncome,
          ),
        _PlanActionSpec(
          icon: FLucideIcons.refreshCw,
          title: l10n.planWheelSectionTitle,
          subtitle: l10n.planWheelSectionSubtitle,
          path: FinanceRoutes.planWheel,
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < Breakpoints.contentTwoColumn) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              nextSteps,
              const SizedBox(height: AppSpacing.s12),
              strategies,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: nextSteps),
            const SizedBox(width: AppSpacing.s20),
            Expanded(child: strategies),
          ],
        );
      },
    );
  }
}

class _PlanActionSection extends StatelessWidget {
  const _PlanActionSection({
    required this.title,
    required this.subtitle,
    required this.actions,
  });

  final String title;
  final String subtitle;
  final List<_PlanActionSpec> actions;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(title: title, subtitle: subtitle),
        AppGroupedActionList(
          actions: [
            for (final spec in actions)
              AppGroupedAction(
                icon: spec.icon,
                title: spec.title,
                subtitle: spec.subtitle,
                onPress: () => context.push(spec.path),
              ),
          ],
        ),
      ],
    );
  }
}

class _PlanActionSpec {
  const _PlanActionSpec({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.path,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String path;
}
