part of 'plan_hub_page.dart';

/// State → UI mapping layer for the Plan hub.
///
/// Translates [PlanningHubStatus] and the FIRE dashboard view into
/// [_PlanEntrySpec] view models (icon, copy, tone, destination). Page
/// composition and widgets stay in `plan_hub_page.dart`; this part only owns
/// the status-to-entry derivation so the page file reads as pure layout.
enum _PlanEntryGroup { cashSafety, longTermGoals, investmentPlan }

class _PlanEntrySpec {
  const _PlanEntrySpec({
    required this.group,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.path,
    required this.tone,
    this.requiresAttention = false,
    this.priority = 100,
  });

  final _PlanEntryGroup group;
  final IconData icon;
  final String title;
  final String subtitle;
  final String path;
  final AppBadgeTone tone;
  final bool requiresAttention;
  final int priority;
}

List<_PlanEntrySpec> _planningEntries(
  BuildContext context,
  AppLocalizations l10n,
  PlanningHubStatus status,
  AsyncValue<FireDashboardView> fire,
) {
  return <_PlanEntrySpec>[
    _runwayEntry(l10n, status),
    _budgetEntry(l10n, status),
    _fireEntry(l10n, fire),
    _dcaEntry(context, l10n, status),
    _rebalanceEntry(l10n, status),
    if (!kIsWeb) _incomeStrategyEntry(l10n, status),
    _lifeEventsEntry(l10n, status),
  ];
}

_PlanEntrySpec _runwayEntry(AppLocalizations l10n, PlanningHubStatus status) {
  final runway = status.runway;
  return _PlanEntrySpec(
    group: _PlanEntryGroup.cashSafety,
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
    requiresAttention:
        runway == PlanningRunwayStatus.watch ||
        runway == PlanningRunwayStatus.shortfall,
    priority: runway == PlanningRunwayStatus.shortfall ? 0 : 5,
  );
}

_PlanEntrySpec _budgetEntry(AppLocalizations l10n, PlanningHubStatus status) {
  final signal = status.budgetSignal;
  final count = status.budgetCount;
  final progress = status.budgetProgress;
  final subtitle = count == null
      ? l10n.planStatusLoading
      : count == 0 || signal == BudgetSignal.noData
      ? l10n.planStatusNeedsSetup
      : signal == BudgetSignal.overBudget
      ? l10n.planStatusBudgetOver
      : signal == BudgetSignal.strained
      ? l10n.planStatusBudgetStrained
      : progress == null
      ? l10n.planStatusBudgetComfortable
      : l10n.planStatusBudgetUsed(
          (progress * 100).clamp(0, 999).toStringAsFixed(0),
        );
  return _PlanEntrySpec(
    group: _PlanEntryGroup.cashSafety,
    icon: FLucideIcons.piggyBank,
    title: l10n.planBudgetSectionTitle,
    subtitle: subtitle,
    path: FinanceRoutes.planBudget,
    tone: switch (signal) {
      BudgetSignal.overBudget => AppBadgeTone.error,
      BudgetSignal.strained => AppBadgeTone.warning,
      BudgetSignal.comfortable => AppBadgeTone.success,
      BudgetSignal.noData || null => AppBadgeTone.neutral,
    },
    requiresAttention:
        signal == BudgetSignal.overBudget || signal == BudgetSignal.strained,
    priority: signal == BudgetSignal.overBudget ? 1 : 6,
  );
}

_PlanEntrySpec _lifeEventsEntry(
  AppLocalizations l10n,
  PlanningHubStatus status,
) {
  final pending = status.pendingLifeEventReviews;
  return _PlanEntrySpec(
    group: _PlanEntryGroup.longTermGoals,
    icon: FLucideIcons.waypoints,
    title: l10n.lifeEventScenariosTitle,
    subtitle: pending == null
        ? l10n.planStatusLoading
        : pending == 0
        ? l10n.planStatusNoPendingReviews
        : l10n.planStatusPendingReviews(pending),
    path: FinanceRoutes.planLifeEvents,
    tone: pending == null
        ? AppBadgeTone.neutral
        : pending > 0
        ? AppBadgeTone.warning
        : AppBadgeTone.success,
    requiresAttention: pending != null && pending > 0,
    priority: 3,
  );
}

_PlanEntrySpec _fireEntry(
  AppLocalizations l10n,
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
    group: _PlanEntryGroup.longTermGoals,
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
  );
}

_PlanEntrySpec _dcaEntry(
  BuildContext context,
  AppLocalizations l10n,
  PlanningHubStatus status,
) => _PlanEntrySpec(
  group: _PlanEntryGroup.investmentPlan,
  icon: FLucideIcons.calendarClock,
  title: l10n.planDcaPlanTitle,
  subtitle: _dcaStatusLabel(context, l10n, status),
  path: FinanceRoutes.planDca,
  tone: status.dcaDue
      ? AppBadgeTone.warning
      : (status.dcaPlanCount ?? 0) > 0
      ? AppBadgeTone.success
      : AppBadgeTone.neutral,
  requiresAttention: status.dcaDue,
  priority: 2,
);

_PlanEntrySpec _incomeStrategyEntry(
  AppLocalizations l10n,
  PlanningHubStatus status,
) {
  final activeOptions = status.wheelOpenPositionCount ?? 0;
  return _PlanEntrySpec(
    group: _PlanEntryGroup.investmentPlan,
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
  group: _PlanEntryGroup.investmentPlan,
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
  requiresAttention: status.rebalance == PlanningRebalanceStatus.attention,
  priority: 4,
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
  final date = MaterialLocalizations.of(context)
      .formatShortDate(nextDue.toLocal());
  return l10n.planStatusDcaNext(date);
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
