part of 'plan_hub_page.dart';

/// State → UI mapping layer for the Plan hub.
///
/// Translates [PlanningHubStatus] and the FIRE dashboard view into
/// [_PlanEntrySpec] view models (icon, copy, tone, destination). Page
/// composition and widgets stay in `plan_hub_page.dart`; this part only owns
/// the status-to-entry derivation so the page file reads as pure layout.
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
  );
}

_PlanEntrySpec _lifeEventsEntry(
  AppLocalizations l10n,
  PlanningHubStatus status,
) {
  final pending = status.pendingLifeEventReviews;
  return _PlanEntrySpec(
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
