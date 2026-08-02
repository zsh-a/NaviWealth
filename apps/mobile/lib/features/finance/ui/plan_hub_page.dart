import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/features/finance/application/read_models/dashboard_providers.dart';
import 'package:naviwealth/features/finance/cashflow/domain/budget_signal.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/finance/fire/data/fire_providers.dart';
import 'package:naviwealth/features/finance/fire/domain/fire_projection.dart';
import 'package:naviwealth/features/finance/investment/data/dca_plan_providers.dart';
import 'package:naviwealth/features/finance/life_events/data/financial_decision_providers.dart';
import 'package:naviwealth/features/finance/options_income/data/providers.dart';
import 'package:naviwealth/features/finance/rebalance/data/rebalance_providers.dart';
import 'package:naviwealth/features/finance/runway/data/money_runway_providers.dart';

import '../../../core/format/formatters.dart';
import '../../../core/shell/shell_chrome.dart';
import '../../../core/shell/shell_visibility.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../application/planning_hub_status.dart';
import '../composition/finance_route_paths.dart';

/// Finance planning workspace.
///
/// The surface is deliberately action-first: due and risky work is promoted,
/// ongoing plans stay visible, and calculators remain secondary.
class PlanHubPage extends ConsumerWidget {
  const PlanHubPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final status = ref.watch(planningHubStatusProvider);
    final fire = ref.watch(fireDashboardViewProvider);
    final attentionItems = _attentionItems(context, status);
    final showNextAction =
        attentionItems.isNotEmpty || status.isLoading || status.hasError;

    return ShellTabScaffold(
      title: l10n.planHubTitle,
      childPad: false,
      child: ShellTabPause(
        routePath: FinanceRoutes.plan,
        placeholder: const SizedBox.expand(),
        child: AdaptiveContentFrame(
          maxWidth: AdaptiveMaxWidth.dashboard,
          expandSinglePrimary: true,
          padding: EdgeInsets.zero,
          primary: AppRefreshIndicator(
            onRefresh: () => _refreshPlanningWorkspace(ref),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: shellTabContentPadding(context, top: AppSpacing.s8),
              children: [
                if (showNextAction) ...[
                  _NextActionSection(status: status, items: attentionItems),
                  const SizedBox(height: AppSpacing.s20),
                ],
                _PlanningSections(
                  status: status,
                  fire: fire,
                  excludedPath: attentionItems.firstOrNull?.path,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _refreshPlanningWorkspace(WidgetRef ref) async {
  final now = DateTime.now();
  final month = '${now.year}-${now.month.toString().padLeft(2, '0')}';
  ref
    ..invalidate(dashboardSnapshotProvider)
    ..invalidate(fireDashboardViewProvider)
    ..invalidate(moneyRunwayProvider)
    ..invalidate(financialDecisionsProvider)
    ..invalidate(activeRebalanceExecutionProvider)
    ..invalidate(rebalancePortfolioSnapshotProvider)
    ..invalidate(monthlyBudgetSummaryProvider(month))
    ..invalidate(dcaPlansProvider)
    ..invalidate(wheelLifecyclesProvider)
    ..invalidate(planningHubStatusProvider);
  try {
    await Future.wait<Object?>([
      ref.read(dashboardSnapshotProvider.future),
      ref.read(financialDecisionsProvider.future),
      ref.read(activeRebalanceExecutionProvider.future),
      ref.read(rebalancePortfolioSnapshotProvider.future),
      ref.read(dcaPlansProvider.future),
    ]);
  } catch (_) {
    // Individual source failures are rendered as a partial-status notice.
  }
}

class _NextActionSection extends StatelessWidget {
  const _NextActionSection({required this.status, required this.items});

  final PlanningHubStatus status;
  final List<_PlanEntrySpec> items;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final next = items.firstOrNull;
    final hasAttention = items.isNotEmpty;
    final tone = next?.tone ?? AppBadgeTone.neutral;
    final icon = hasAttention ? next!.icon : FLucideIcons.loaderCircle;

    return SoftCard.raised(
      padding: AppPageRhythm.cardPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.planAttentionTitle,
                  style: context.mutedLabelStyle,
                ),
              ),
              if (hasAttention || status.isLoading)
                AppBadge(
                  label: status.isLoading && !hasAttention
                      ? l10n.commonLoading
                      : _toneLabel(context, tone),
                  size: AppBadgeSize.compact,
                  tone: status.isLoading && !hasAttention
                      ? AppBadgeTone.neutral
                      : tone,
                  icon: icon,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.s12),
          if (hasAttention)
            _AttentionRow(spec: next!)
          else if (status.isLoading)
            const _AttentionSkeleton()
          else if (!status.hasError)
            const SizedBox.shrink(),
          if (status.hasError) ...[
            const SizedBox(height: AppSpacing.s12),
            Row(
              children: [
                Icon(
                  FLucideIcons.cloudAlert,
                  size: AppIconSizes.sm,
                  color: context.appTheme.status.warning.fg,
                ),
                const SizedBox(width: AppSpacing.s6),
                Expanded(
                  child: Text(
                    l10n.planStatusPartiallyUnavailable,
                    style: context.captionStyle,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _AttentionRow extends StatelessWidget {
  const _AttentionRow({required this.spec});

  final _PlanEntrySpec spec;

  @override
  Widget build(BuildContext context) {
    final color = _toneColor(context, spec.tone);
    return SoftCard.flat(
      tinted: false,
      onPress: () => context.push(spec.path),
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: AppOpacity.subtle),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            alignment: Alignment.center,
            child: Icon(spec.icon, size: AppIconSizes.sm, color: color),
          ),
          const SizedBox(width: AppSpacing.s10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(spec.title, style: context.labelStyle),
                const SizedBox(height: AppSpacing.s2),
                Text(spec.subtitle, style: context.captionStyle),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.s8),
          Icon(
            FLucideIcons.chevronRight,
            size: AppIconSizes.sm,
            color: context.theme.colors.mutedForeground,
          ),
        ],
      ),
    );
  }
}

class _AttentionSkeleton extends StatelessWidget {
  const _AttentionSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        SkeletonBox(width: 36, height: 36, radius: AppRadius.sm),
        SizedBox(width: AppSpacing.s10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 160, height: 16, radius: AppRadius.sm),
              SizedBox(height: AppSpacing.s6),
              SkeletonBox(width: 220, height: 12, radius: AppRadius.sm),
            ],
          ),
        ),
      ],
    );
  }
}

class _PlanningSections extends StatelessWidget {
  const _PlanningSections({
    required this.status,
    required this.fire,
    required this.excludedPath,
  });

  final PlanningHubStatus status;
  final AsyncValue<FireDashboardView> fire;
  final String? excludedPath;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final formatters = AppFormatters(locale: Localizations.localeOf(context));
    final outlook = <_PlanEntrySpec>[
      _runwayEntry(l10n, status),
      _fireEntry(l10n, formatters, fire),
    ].where((entry) => entry.path != excludedPath).toList(growable: false);
    final investments = <_PlanEntrySpec>[
      if ((status.dcaPlanCount ?? 0) > 0) _dcaEntry(context, l10n, status),
      if (status.rebalance == PlanningRebalanceStatus.attention ||
          status.rebalance == PlanningRebalanceStatus.active)
        _rebalanceEntry(l10n, status),
      if (!kIsWeb && (status.wheelCycleCount ?? 0) > 0)
        _incomeStrategyEntry(l10n, status),
    ].where((entry) => entry.path != excludedPath).toList(growable: false);
    final reviews = <_PlanEntrySpec>[
      if ((status.pendingLifeEventReviews ?? 0) > 0)
        _PlanEntrySpec(
          icon: FLucideIcons.waypoints,
          title: l10n.lifeEventScenariosTitle,
          subtitle: status.pendingLifeEventReviews == null
              ? l10n.planStatusLoading
              : status.pendingLifeEventReviews == 0
              ? l10n.planStatusNoPendingReviews
              : l10n.planStatusPendingReviews(status.pendingLifeEventReviews!),
          path: FinanceRoutes.planLifeEvents,
          tone: status.pendingLifeEventReviews == null
              ? AppBadgeTone.neutral
              : status.pendingLifeEventReviews! > 0
              ? AppBadgeTone.warning
              : AppBadgeTone.success,
        ),
    ].where((entry) => entry.path != excludedPath).toList(growable: false);
    final overviewSpan = investments.isNotEmpty || reviews.isNotEmpty
        ? AdaptiveSummaryTileRole.supporting
        : AdaptiveSummaryTileRole.continuous;
    final companion = investments.isNotEmpty
        ? _PlanSection(
            key: const ValueKey('plan-investments-section'),
            title: l10n.planMyPlansTitle,
            entries: investments,
          )
        : reviews.isNotEmpty
        ? _PlanSection(
            key: const ValueKey('plan-reviews-section'),
            title: l10n.lifeEventDecisionHistory,
            entries: reviews,
          )
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdaptiveSummaryGrid(
          gap: AppSpacing.s20,
          items: [
            AdaptiveSummaryTile(
              role: overviewSpan,
              child: _PlanSection(
                key: const ValueKey('plan-outlook-section'),
                title: l10n.planOverviewTitle,
                entries: outlook,
              ),
            ),
            if (companion != null)
              AdaptiveSummaryTile(
                role: AdaptiveSummaryTileRole.featured,
                child: companion,
              ),
            if (investments.isNotEmpty && reviews.isNotEmpty)
              AdaptiveSummaryTile(
                role: AdaptiveSummaryTileRole.continuous,
                child: _PlanSection(
                  key: const ValueKey('plan-reviews-section'),
                  title: l10n.lifeEventDecisionHistory,
                  entries: reviews,
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.s12),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: AppAdaptiveActionMenu(
            title: l10n.planAddPlanAction,
            actions: [
              AppAdaptiveAction(
                icon: FLucideIcons.piggyBank,
                title: l10n.planBudgetSectionTitle,
                onPress: () => context.push(FinanceRoutes.planBudget),
              ),
              AppAdaptiveAction(
                icon: FLucideIcons.scale,
                title: l10n.planRebalanceSectionTitle,
                onPress: () => context.push(FinanceRoutes.planRebalance),
              ),
              AppAdaptiveAction(
                icon: FLucideIcons.calendarClock,
                title: l10n.planDcaPlanTitle,
                onPress: () => context.push(FinanceRoutes.planDca),
              ),
              if (!kIsWeb)
                AppAdaptiveAction(
                  icon: FLucideIcons.candlestickChart,
                  title: l10n.incomeStrategyTitle,
                  onPress: () => context.push(FinanceRoutes.planIncome),
                ),
              AppAdaptiveAction(
                icon: FLucideIcons.waypoints,
                title: l10n.lifeEventScenariosTitle,
                onPress: () => context.push(FinanceRoutes.planLifeEvents),
              ),
            ],
            triggerBuilder: (context, openMenu, focusNode) => FButton(
              variant: FButtonVariant.ghost,
              focusNode: focusNode,
              onPress: openMenu,
              prefix: const Icon(FLucideIcons.plus, size: AppIconSizes.sm),
              child: Flexible(
                child: Text(
                  l10n.planAddPlanAction,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PlanSection extends StatelessWidget {
  const _PlanSection({super.key, required this.title, required this.entries});

  final String title;
  final List<_PlanEntrySpec> entries;

  @override
  Widget build(BuildContext context) {
    return AppSection.group(
      title: title,
      children: [
        for (final (index, entry) in entries.indexed) ...[
          if (index > 0) const FDivider(),
          _PlanRow(spec: entry),
        ],
      ],
    );
  }
}

class _PlanRow extends StatelessWidget {
  const _PlanRow({required this.spec});

  final _PlanEntrySpec spec;

  @override
  Widget build(BuildContext context) {
    final color = _toneColor(context, spec.tone);
    return SoftCard.flat(
      tinted: false,
      onPress: () => context.push(spec.path),
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s6),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: AppOpacity.subtle),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            alignment: Alignment.center,
            child: Icon(spec.icon, size: AppIconSizes.sm, color: color),
          ),
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
                const SizedBox(height: AppSpacing.s2),
                Text(
                  spec.subtitle,
                  style: context.captionStyle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (spec.tone == AppBadgeTone.warning ||
                    spec.tone == AppBadgeTone.error) ...[
                  const SizedBox(height: AppSpacing.s4),
                  AppBadge(
                    label: spec.badge ?? _toneLabel(context, spec.tone),
                    tone: spec.tone,
                    size: AppBadgeSize.compact,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.s8),
          Icon(
            FLucideIcons.chevronRight,
            size: AppIconSizes.sm,
            color: context.theme.colors.mutedForeground,
          ),
        ],
      ),
    );
  }
}

class _PlanEntrySpec {
  const _PlanEntrySpec({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.path,
    required this.tone,
    this.badge,
    this.priority = 100,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String path;
  final AppBadgeTone tone;
  final String? badge;
  final int priority;
}

List<_PlanEntrySpec> _attentionItems(
  BuildContext context,
  PlanningHubStatus status,
) {
  final l10n = AppLocalizations.of(context);
  final items = <_PlanEntrySpec>[
    if (status.runway == PlanningRunwayStatus.shortfall)
      _PlanEntrySpec(
        icon: FLucideIcons.triangleAlert,
        title: l10n.moneyRunwayTitle,
        subtitle: l10n.moneyRunwayStatusShortfall,
        path: FinanceRoutes.planRunway,
        tone: AppBadgeTone.error,
        priority: 0,
      ),
    if (status.budgetSignal == BudgetSignal.overBudget)
      _PlanEntrySpec(
        icon: FLucideIcons.piggyBank,
        title: l10n.planBudgetSectionTitle,
        subtitle: l10n.planStatusBudgetOver,
        path: FinanceRoutes.planBudget,
        tone: AppBadgeTone.error,
        priority: 1,
      ),
    if (status.dcaDue)
      _PlanEntrySpec(
        icon: FLucideIcons.calendarClock,
        title: l10n.planDcaPlanTitle,
        subtitle: l10n.planStatusDcaDue,
        path: FinanceRoutes.planDca,
        tone: AppBadgeTone.warning,
        priority: 2,
      ),
    if ((status.pendingLifeEventReviews ?? 0) > 0)
      _PlanEntrySpec(
        icon: FLucideIcons.waypoints,
        title: l10n.lifeEventScenariosTitle,
        subtitle: l10n.planStatusPendingReviews(
          status.pendingLifeEventReviews!,
        ),
        path: FinanceRoutes.planLifeEvents,
        tone: AppBadgeTone.warning,
        priority: 3,
      ),
    if (status.rebalance == PlanningRebalanceStatus.attention)
      _PlanEntrySpec(
        icon: FLucideIcons.scale,
        title: l10n.planRebalanceSectionTitle,
        subtitle: _rebalanceStatusLabel(l10n, status),
        path: FinanceRoutes.planRebalance,
        tone: AppBadgeTone.warning,
        priority: 4,
      ),
    if (status.runway == PlanningRunwayStatus.watch)
      _PlanEntrySpec(
        icon: FLucideIcons.calendarRange,
        title: l10n.moneyRunwayTitle,
        subtitle: l10n.moneyRunwayStatusWatch,
        path: FinanceRoutes.planRunway,
        tone: AppBadgeTone.warning,
        priority: 5,
      ),
    if (status.budgetSignal == BudgetSignal.strained)
      _PlanEntrySpec(
        icon: FLucideIcons.gauge,
        title: l10n.planBudgetSectionTitle,
        subtitle: l10n.planStatusBudgetStrained,
        path: FinanceRoutes.planBudget,
        tone: AppBadgeTone.warning,
        priority: 6,
      ),
    if (status.rebalance == PlanningRebalanceStatus.active)
      _PlanEntrySpec(
        icon: FLucideIcons.listChecks,
        title: l10n.planRebalanceSectionTitle,
        subtitle: l10n.planStatusRebalanceActive,
        path: FinanceRoutes.planRebalance,
        tone: AppBadgeTone.accent,
        priority: 7,
      ),
  ]..sort((a, b) => a.priority.compareTo(b.priority));
  return items;
}

_PlanEntrySpec _runwayEntry(AppLocalizations l10n, PlanningHubStatus status) {
  final runway = status.runway;
  return _PlanEntrySpec(
    icon: FLucideIcons.calendarRange,
    title: l10n.moneyRunwayTitle,
    subtitle: _runwayStatusLabel(l10n, runway),
    path: FinanceRoutes.planRunway,
    tone: switch (runway) {
      PlanningRunwayStatus.healthy => AppBadgeTone.success,
      PlanningRunwayStatus.watch => AppBadgeTone.warning,
      PlanningRunwayStatus.shortfall => AppBadgeTone.error,
      PlanningRunwayStatus.needsData || null => AppBadgeTone.neutral,
    },
  );
}

_PlanEntrySpec _fireEntry(
  AppLocalizations l10n,
  AppFormatters formatters,
  AsyncValue<FireDashboardView> fire,
) {
  final view = fire.value;
  final progress = view?.progressRatio;
  final liveScenario = view?.scenarios.firstWhereOrNull(
    (scenario) => scenario.tier == FireScenarioTier.live,
  );
  final neutralScenario = view?.scenarios.firstWhereOrNull(
    (scenario) => scenario.tier == FireScenarioTier.neutral,
  );
  final months = (liveScenario ?? neutralScenario)?.monthsToTarget;
  final years = months == null
      ? null
      : (months / 12).toStringAsFixed(months < 24 ? 1 : 0);
  return _PlanEntrySpec(
    icon: FLucideIcons.mountain,
    title: l10n.planFireGoalTitle,
    subtitle: fire.isLoading
        ? l10n.planStatusLoading
        : fire.hasError
        ? l10n.planStatusUnavailable
        : progress == null
        ? l10n.planFireGoalNotConfigured
        : years != null
        ? l10n.planHeroYearsToFire(years)
        : l10n.planStatusFireProgress(
            (progress * 100).clamp(0, 100).toStringAsFixed(0),
          ),
    path: FinanceRoutes.planFire,
    tone: progress == null ? AppBadgeTone.neutral : AppBadgeTone.accent,
    badge: progress == null
        ? l10n.planStatusNeedsSetup
        : formatters.percent(progress.clamp(0, 1), decimalDigits: 0),
  );
}

_PlanEntrySpec _dcaEntry(
  BuildContext context,
  AppLocalizations l10n,
  PlanningHubStatus status,
) => _PlanEntrySpec(
  icon: FLucideIcons.calendarClock,
  title: l10n.planDcaPlanTitle,
  subtitle: _dcaStatusLabel(context, l10n, status),
  path: FinanceRoutes.planDca,
  tone: status.dcaDue
      ? AppBadgeTone.warning
      : (status.dcaPlanCount ?? 0) > 0
      ? AppBadgeTone.success
      : AppBadgeTone.neutral,
);

_PlanEntrySpec _incomeStrategyEntry(
  AppLocalizations l10n,
  PlanningHubStatus status,
) {
  final activeOptions = status.wheelOpenPositionCount ?? 0;
  return _PlanEntrySpec(
    icon: FLucideIcons.candlestickChart,
    title: l10n.incomeStrategyTitle,
    subtitle: activeOptions > 0
        ? l10n.planExploreActiveOptions(activeOptions)
        : l10n.planIncomeSectionSubtitle,
    path: FinanceRoutes.planIncome,
    tone: activeOptions > 0 ? AppBadgeTone.accent : AppBadgeTone.neutral,
  );
}

_PlanEntrySpec _rebalanceEntry(
  AppLocalizations l10n,
  PlanningHubStatus status,
) => _PlanEntrySpec(
  icon: FLucideIcons.scale,
  title: l10n.planRebalanceSectionTitle,
  subtitle: _rebalanceStatusLabel(l10n, status),
  path: FinanceRoutes.planRebalance,
  tone: switch (status.rebalance) {
    PlanningRebalanceStatus.balanced => AppBadgeTone.success,
    PlanningRebalanceStatus.attention => AppBadgeTone.warning,
    PlanningRebalanceStatus.active => AppBadgeTone.accent,
    PlanningRebalanceStatus.needsData || null => AppBadgeTone.neutral,
  },
);

String _runwayStatusLabel(
  AppLocalizations l10n,
  PlanningRunwayStatus? status,
) => switch (status) {
  null => l10n.planStatusLoading,
  PlanningRunwayStatus.needsData => l10n.planStatusNeedsSetup,
  PlanningRunwayStatus.healthy => l10n.moneyRunwayStatusHealthy,
  PlanningRunwayStatus.watch => l10n.moneyRunwayStatusWatch,
  PlanningRunwayStatus.shortfall => l10n.moneyRunwayStatusShortfall,
};

String _rebalanceStatusLabel(AppLocalizations l10n, PlanningHubStatus status) =>
    switch (status.rebalance) {
      null => l10n.planStatusLoading,
      PlanningRebalanceStatus.needsData => l10n.planStatusNeedsSetup,
      PlanningRebalanceStatus.balanced => l10n.planStatusRebalanceBalanced,
      PlanningRebalanceStatus.attention => l10n.planStatusRebalanceAttention(
        ((status.rebalanceDriftPct ?? 0) * 100).toStringAsFixed(1),
      ),
      PlanningRebalanceStatus.active => l10n.planStatusRebalanceActive,
    };

String _dcaStatusLabel(
  BuildContext context,
  AppLocalizations l10n,
  PlanningHubStatus status,
) {
  if (status.dcaPlanCount == null) return l10n.planStatusLoading;
  if (status.dcaPlanCount == 0) return l10n.planStatusNeedsSetup;
  final nextDue = status.dcaNextDueAt;
  if (nextDue == null) return l10n.planStatusDcaPaused;
  if (status.dcaDue) return l10n.planStatusDcaDue;
  final date = MaterialLocalizations.of(
    context,
  ).formatShortDate(nextDue.toLocal());
  return l10n.planStatusDcaNext(date);
}

Color _toneColor(BuildContext context, AppBadgeTone tone) {
  final colors = context.theme.colors;
  final status = context.appTheme.status;
  return switch (tone) {
    AppBadgeTone.neutral => colors.mutedForeground,
    AppBadgeTone.accent => colors.primary,
    AppBadgeTone.info => status.info.fg,
    AppBadgeTone.success => status.success.fg,
    AppBadgeTone.warning => status.warning.fg,
    AppBadgeTone.error => status.danger.fg,
  };
}

String _toneLabel(BuildContext context, AppBadgeTone tone) {
  final l10n = AppLocalizations.of(context);
  return switch (tone) {
    AppBadgeTone.neutral => l10n.planStatusView,
    AppBadgeTone.accent => l10n.planStatusInProgress,
    AppBadgeTone.info => l10n.planStatusView,
    AppBadgeTone.success => l10n.planStatusOnTrack,
    AppBadgeTone.warning => l10n.planStatusNeedsAttention,
    AppBadgeTone.error => l10n.planStatusActionRequired,
  };
}
