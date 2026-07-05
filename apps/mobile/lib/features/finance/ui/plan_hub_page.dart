import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
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
              kTabBarOffset + MediaQuery.paddingOf(context).bottom,
            ),
            children: const [
              _FireSummaryCard(),
              SizedBox(height: AppSpacing.s16),
              _PlanActions(),
            ],
          );
        },
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
      loading: () => const SoftCard(
        padding: EdgeInsets.all(AppSpacing.s20),
        borderRadius: AppRadius.xlg,
        borderless: true,
        tinted: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SkeletonBox(width: 120, height: 16, radius: AppRadius.xs),
            SizedBox(height: AppSpacing.s8),
            SkeletonBox(width: 220, height: 34, radius: AppRadius.sm),
            SizedBox(height: AppSpacing.s16),
            SkeletonBox(height: 10, radius: AppRadius.full),
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
    return SoftCard(
      padding: const EdgeInsets.all(AppSpacing.s16),
      borderRadius: AppRadius.lg,
      borderless: true,
      tinted: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.planHubTitle, style: context.mutedLabelStyle),
          const SizedBox(height: AppSpacing.s8),
          Text(l10n.planHeroEmpty, style: context.theme.typography.body.md),
          const SizedBox(height: AppSpacing.s16),
          FButton(
            variant: FButtonVariant.primary,
            onPress: () => context.push(FinanceRoutes.planFire),
            child: Text(l10n.planHeroSeePlan),
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
    return SoftCard(
      padding: EdgeInsets.zero,
      borderRadius: AppRadius.lg,
      borderless: true,
      tinted: false,
      child: AppEmptyState.error(
        title: l10n.commonLoadFailed,
        message: '$error',
        action: FButton(
          variant: FButtonVariant.ghost,
          onPress: () => ref.invalidate(fireDashboardViewProvider),
          child: Text(l10n.commonRetry),
        ),
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
    return SoftCard(
      padding: const EdgeInsets.all(AppSpacing.s16),
      borderRadius: AppRadius.lg,
      borderless: true,
      tinted: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.planFireSectionTitle, style: context.mutedLabelStyle),
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
          FDeterminateProgress(value: progress),
          const SizedBox(height: AppSpacing.s8),
          Text(
            '${l10n.planHeroProgressLabel} $progressPct%',
            style: context.captionStyle,
          ),
          const SizedBox(height: AppSpacing.s16),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FButton(
                variant: FButtonVariant.primary,
                onPress: () => context.push(FinanceRoutes.planFire),
                child: Text(l10n.planHeroSeePlan),
              ),
              const SizedBox(width: AppSpacing.s8),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PlanActionSection(
          title: l10n.planCoreSectionTitle,
          subtitle: l10n.planCoreSectionSubtitle,
          actions: [
            _PlanActionSpec(
              icon: FLucideIcons.flame,
              title: l10n.planFireSectionTitle,
              subtitle: l10n.planFireSectionSubtitle,
              path: FinanceRoutes.planFire,
            ),
            _PlanActionSpec(
              icon: FLucideIcons.scale,
              title: l10n.planRebalanceSectionTitle,
              subtitle: l10n.planRebalanceSectionSubtitle,
              path: FinanceRoutes.planRebalance,
            ),
            _PlanActionSpec(
              icon: FLucideIcons.piggyBank,
              title: l10n.planBudgetSectionTitle,
              subtitle: l10n.planBudgetSectionSubtitle,
              path: FinanceRoutes.planBudget,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.s8),
        _PlanActionSection(
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
              icon: FLucideIcons.calendarClock,
              title: l10n.planDcaSectionTitle,
              subtitle: l10n.planDcaSectionSubtitle,
              path: FinanceRoutes.planDca,
            ),
            _PlanActionSpec(
              icon: FLucideIcons.refreshCw,
              title: l10n.planWheelSectionTitle,
              subtitle: l10n.planWheelSectionSubtitle,
              path: FinanceRoutes.planWheel,
            ),
          ],
        ),
      ],
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
