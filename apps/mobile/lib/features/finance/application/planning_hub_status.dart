import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../cashflow/domain/budget_signal.dart';
import '../data/repositories/providers.dart';
import '../investment/data/dca_plan_providers.dart';
import '../life_events/data/financial_decision_providers.dart';
import '../options_income/data/providers.dart';
import '../rebalance/data/rebalance_providers.dart';
import '../runway/data/money_runway_providers.dart';
import '../runway/domain/money_runway.dart';

enum PlanningRunwayStatus { needsData, healthy, watch, shortfall }

enum PlanningRebalanceStatus { needsData, balanced, attention, active }

final class PlanningHubStatus {
  const PlanningHubStatus({
    required this.runway,
    required this.pendingLifeEventReviews,
    required this.rebalance,
    required this.rebalanceDriftPct,
    required this.budgetCount,
    required this.budgetSignal,
    required this.budgetProgress,
    required this.dcaPlanCount,
    required this.dcaNextDueAt,
    required this.dcaDue,
    required this.wheelCycleCount,
    required this.wheelOpenPositionCount,
    required this.isLoading,
    required this.hasError,
  });

  const PlanningHubStatus.loading()
    : runway = null,
      pendingLifeEventReviews = null,
      rebalance = null,
      rebalanceDriftPct = null,
      budgetCount = null,
      budgetSignal = null,
      budgetProgress = null,
      dcaPlanCount = null,
      dcaNextDueAt = null,
      dcaDue = false,
      wheelCycleCount = null,
      wheelOpenPositionCount = null,
      isLoading = true,
      hasError = false;

  final PlanningRunwayStatus? runway;
  final int? pendingLifeEventReviews;
  final PlanningRebalanceStatus? rebalance;
  final double? rebalanceDriftPct;
  final int? budgetCount;
  final BudgetSignal? budgetSignal;
  final double? budgetProgress;
  final int? dcaPlanCount;
  final DateTime? dcaNextDueAt;
  final bool dcaDue;
  final int? wheelCycleCount;
  final int? wheelOpenPositionCount;
  final bool isLoading;
  final bool hasError;
}

final planningHubStatusProvider = Provider.autoDispose<PlanningHubStatus>((
  ref,
) {
  final runwayAsync = ref.watch(moneyRunwayProvider);
  final decisionsAsync = ref.watch(financialDecisionsProvider);
  final activeRebalanceAsync = ref.watch(activeRebalanceExecutionProvider);
  final rebalanceSnapshot = ref.watch(rebalancePortfolioSnapshotProvider);
  final rebalancePlan = ref.watch(rebalancePlanProvider);
  final now = DateTime.now();
  final month = '${now.year}-${now.month.toString().padLeft(2, '0')}';
  final budgetSummaryAsync = ref.watch(monthlyBudgetSummaryProvider(month));
  final dcaPlansAsync = ref.watch(dcaPlansProvider);
  final wheelCyclesAsync = ref.watch(wheelLifecyclesProvider);

  final runway = runwayAsync.value;
  final decisions = decisionsAsync.value;
  final activeRebalance = activeRebalanceAsync.value;
  final budgetSummary = budgetSummaryAsync.value?.summary;
  final dcaPlans = dcaPlansAsync.value;
  final wheelCycles = wheelCyclesAsync.value;
  final asyncSources = <AsyncValue<Object?>>[
    runwayAsync,
    decisionsAsync,
    activeRebalanceAsync,
    rebalanceSnapshot,
    budgetSummaryAsync,
    dcaPlansAsync,
    wheelCyclesAsync,
  ];

  final enabledDcaPlans =
      dcaPlans?.where((plan) => plan.enabled).toList(growable: false)
        ?..sort((a, b) => a.nextDueAt.compareTo(b.nextDueAt));
  final nextDca = enabledDcaPlans?.firstOrNull;

  return PlanningHubStatus(
    runway: runway == null
        ? null
        : !runway.hasData
        ? PlanningRunwayStatus.needsData
        : switch (runway.status) {
            MoneyRunwayStatus.healthy => PlanningRunwayStatus.healthy,
            MoneyRunwayStatus.watch => PlanningRunwayStatus.watch,
            MoneyRunwayStatus.shortfall => PlanningRunwayStatus.shortfall,
          },
    pendingLifeEventReviews: decisions
        ?.where(
          (decision) =>
              decision.reviewedAt == null && !decision.reviewDate.isAfter(now),
        )
        .length,
    rebalance: activeRebalance != null
        ? PlanningRebalanceStatus.active
        : !rebalanceSnapshot.hasValue
        ? null
        : rebalancePlan == null
        ? PlanningRebalanceStatus.needsData
        : rebalancePlan.isBalanced
        ? PlanningRebalanceStatus.balanced
        : PlanningRebalanceStatus.attention,
    rebalanceDriftPct: rebalancePlan?.driftBeforePct,
    budgetCount: budgetSummary?.categories.length,
    budgetSignal: budgetSummary == null ? null : budgetSignalFor(budgetSummary),
    budgetProgress: budgetSummary?.progressFraction,
    dcaPlanCount: dcaPlans?.length,
    dcaNextDueAt: nextDca?.nextDueAt,
    dcaDue: nextDca?.isDue ?? false,
    wheelCycleCount: wheelCycles?.length,
    wheelOpenPositionCount: wheelCycles
        ?.where((cycle) => cycle.hasOpenPosition)
        .length,
    isLoading: asyncSources.any((source) => source.isLoading),
    hasError: asyncSources.any((source) => source.hasError),
  );
});
