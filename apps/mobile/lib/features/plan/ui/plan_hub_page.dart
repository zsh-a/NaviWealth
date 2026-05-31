import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/route_paths.dart';
import '../../../app/shell_chrome.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../fire/data/fire_providers.dart';
import '../../fire/domain/fire_projection.dart';

/// Plan hub — landing page for the Plan tab.
///
/// IA contract §1: Plan is "decisions + future state". The hub renders a
/// FIRE-progress hero (years-to-FIRE pulled from [fireDashboardViewProvider])
/// and a section grid that links into each sub-decision surface — FIRE,
/// Rebalance, Income strategy, DCA, Scenario analytics, Scenarios, Goals.
///
/// Phase A landed the routing scaffold; Phase B (this implementation) puts a
/// real hero on the hub so it isn't a link list.
class PlanHubPage extends ConsumerWidget {
  const PlanHubPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return ShellTabScaffold(
      title: l10n.planHubTitle,
      childPad: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final hPad = Breakpoints.isMobile(width)
              ? AppSpacing.s16
              : AppSpacing.s24;
          return ListView(
            padding: EdgeInsets.fromLTRB(
              hPad,
              AppSpacing.s12,
              hPad,
              AppSpacing.s24 + MediaQuery.paddingOf(context).bottom,
            ),
            children: const [
              _PlanHero(),
              SizedBox(height: AppSpacing.s20),
              _PlanSectionGrid(),
            ],
          );
        },
      ),
    );
  }
}

/// FIRE-progress hero. Reads [fireDashboardViewProvider] and renders a
/// large "X years to FIRE" headline + progress chip + see-plan CTA. When
/// no FIRE goal is set, falls back to a single setup CTA.
class _PlanHero extends ConsumerWidget {
  const _PlanHero();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final viewAsync = ref.watch(fireDashboardViewProvider);

    return viewAsync.when(
      loading: () => const SoftCard(
        padding: EdgeInsets.all(AppSpacing.s20),
        child: SizedBox(height: 96, child: Center(child: FCircularProgress())),
      ),
      error: (_, _) => _emptyHero(context, l10n),
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
        return _hero(
          context: context,
          l10n: l10n,
          progress: progress,
          monthsToTarget: scenario?.monthsToTarget,
        );
      },
    );
  }

  Widget _emptyHero(BuildContext context, AppLocalizations l10n) {
    final colors = context.theme.colors;
    return SoftCard(
      padding: const EdgeInsets.all(AppSpacing.s20),
      borderRadius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.planHubTitle,
            style: context.theme.typography.sm.copyWith(
              color: colors.mutedForeground,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.s8),
          Text(l10n.planHeroEmpty, style: context.theme.typography.md),
          const SizedBox(height: AppSpacing.s16),
          FButton(
            variant: FButtonVariant.primary,
            onPress: () => context.push(AppRoutes.planFire),
            child: Text(l10n.planHeroSeePlan),
          ),
        ],
      ),
    );
  }

  Widget _hero({
    required BuildContext context,
    required AppLocalizations l10n,
    required double progress,
    required int? monthsToTarget,
  }) {
    final colors = context.theme.colors;
    final years = monthsToTarget == null
        ? null
        : (monthsToTarget / 12).toStringAsFixed(monthsToTarget < 24 ? 1 : 0);
    final progressPct = (progress * 100).clamp(0, 100).toStringAsFixed(0);
    return SoftCard(
      padding: const EdgeInsets.all(AppSpacing.s20),
      borderRadius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.planFireSectionTitle,
            style: context.theme.typography.sm.copyWith(
              color: colors.mutedForeground,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.s8),
          if (years != null)
            Text(
              l10n.planHeroYearsToFire(years),
              style: TypographyTokens.numericDisplay,
            )
          else
            Text(
              '${l10n.planHeroProgressLabel} $progressPct%',
              style: TypographyTokens.numericTitle,
            ),
          const SizedBox(height: AppSpacing.s12),
          LinearProgressIndicator(
            value: progress,
            minHeight: 6,
            backgroundColor: colors.muted,
            valueColor: AlwaysStoppedAnimation<Color>(colors.primary),
          ),
          const SizedBox(height: AppSpacing.s8),
          Text(
            '${l10n.planHeroProgressLabel} $progressPct%',
            style: context.theme.typography.xs.copyWith(
              color: colors.mutedForeground,
            ),
          ),
          const SizedBox(height: AppSpacing.s16),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FButton(
                variant: FButtonVariant.primary,
                onPress: () => context.push(AppRoutes.planFire),
                child: Text(l10n.planHeroSeePlan),
              ),
              const SizedBox(width: AppSpacing.s8),
              FButton(
                variant: FButtonVariant.outline,
                onPress: () => context.push(AppRoutes.planRebalance),
                child: Text(l10n.planHeroNextRebalance),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PlanSectionGrid extends StatelessWidget {
  const _PlanSectionGrid();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sections = <_PlanSectionSpec>[
      _PlanSectionSpec(
        icon: FLucideIcons.flame,
        title: l10n.planFireSectionTitle,
        subtitle: l10n.planFireSectionSubtitle,
        path: AppRoutes.planFire,
      ),
      _PlanSectionSpec(
        icon: FLucideIcons.scale,
        title: l10n.planRebalanceSectionTitle,
        subtitle: l10n.planRebalanceSectionSubtitle,
        path: AppRoutes.planRebalance,
      ),
      _PlanSectionSpec(
        icon: FLucideIcons.candlestickChart,
        title: l10n.planIncomeSectionTitle,
        subtitle: l10n.planIncomeSectionSubtitle,
        path: AppRoutes.planIncome,
      ),
      _PlanSectionSpec(
        icon: FLucideIcons.calendarClock,
        title: l10n.planDcaSectionTitle,
        subtitle: l10n.planDcaSectionSubtitle,
        path: AppRoutes.planDca,
      ),
      _PlanSectionSpec(
        icon: FLucideIcons.piggyBank,
        title: l10n.planBudgetSectionTitle,
        subtitle: l10n.planBudgetSectionSubtitle,
        path: AppRoutes.planBudget,
      ),
      _PlanSectionSpec(
        icon: FLucideIcons.refreshCw,
        title: l10n.planWheelSectionTitle,
        subtitle: l10n.planWheelSectionSubtitle,
        path: AppRoutes.planWheel,
      ),
      _PlanSectionSpec(
        icon: FLucideIcons.chartLine,
        title: l10n.planProjectionSectionTitle,
        subtitle: l10n.planProjectionSectionSubtitle,
        path: AppRoutes.planProjection,
      ),
      _PlanSectionSpec(
        icon: FLucideIcons.arrowLeftRight,
        title: l10n.planScenariosSectionTitle,
        subtitle: l10n.planScenariosSectionSubtitle,
        path: AppRoutes.planScenarios,
      ),
      _PlanSectionSpec(
        icon: FLucideIcons.flag,
        title: l10n.planGoalsSectionTitle,
        subtitle: l10n.planGoalsSectionSubtitle,
        path: AppRoutes.planGoals,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumn = constraints.maxWidth >= 620;
        if (!twoColumn) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final spec in sections) ...[
                _PlanSectionCard(spec: spec),
                const SizedBox(height: AppSpacing.s12),
              ],
            ],
          );
        }
        // Two-column grid for tablet+desktop.
        final rows = <Widget>[];
        for (var i = 0; i < sections.length; i += 2) {
          final left = sections[i];
          final right = i + 1 < sections.length ? sections[i + 1] : null;
          rows.add(
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.s12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _PlanSectionCard(spec: left)),
                  const SizedBox(width: AppSpacing.s12),
                  Expanded(
                    child: right == null
                        ? const SizedBox()
                        : _PlanSectionCard(spec: right),
                  ),
                ],
              ),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: rows,
        );
      },
    );
  }
}

class _PlanSectionSpec {
  const _PlanSectionSpec({
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

class _PlanSectionCard extends StatelessWidget {
  const _PlanSectionCard({required this.spec});

  final _PlanSectionSpec spec;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return SoftCard(
      child: FTile(
        onPress: () => context.push(spec.path),
        prefix: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: colors.foreground.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          alignment: Alignment.center,
          child: Icon(spec.icon, size: AppIconSizes.h18, color: colors.mutedForeground),
        ),
        title: Text(spec.title),
        subtitle: Text(spec.subtitle),
        suffix: const Icon(FLucideIcons.chevronRight, size: AppIconSizes.h18),
      ),
    );
  }
}

/// Placeholder page for /plan/scenarios.
/// Phase B+ ships the real scenario builder; until then this surfaces a
/// "coming soon" empty state so the route resolves cleanly.
class PlanScenariosPlaceholderPage extends StatelessWidget {
  const PlanScenariosPlaceholderPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return FScaffold(
      header: FHeader.nested(title: Text(l10n.planScenariosSectionTitle)),
      childPad: false,
      child: Center(
        child: AppEmptyState(
          icon: FLucideIcons.arrowLeftRight,
          title: l10n.planScenariosComingSoon,
        ),
      ),
    );
  }
}

/// Placeholder page for /plan/goals — see [PlanScenariosPlaceholderPage].
class PlanGoalsPlaceholderPage extends StatelessWidget {
  const PlanGoalsPlaceholderPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return FScaffold(
      header: FHeader.nested(title: Text(l10n.planGoalsSectionTitle)),
      childPad: false,
      child: Center(
        child: AppEmptyState(
          icon: FLucideIcons.flag,
          title: l10n.planGoalsComingSoon,
        ),
      ),
    );
  }
}
