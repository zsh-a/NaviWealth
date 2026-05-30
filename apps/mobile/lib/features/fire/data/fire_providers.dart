import 'package:collection/collection.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/values/money.dart';
import '../../cashflow/data/cash_flow_providers.dart';
import '../../cashflow/domain/cash_flow_aggregator.dart';
import '../../cashflow/domain/cash_flow_kind.dart';
import '../../home/data/dashboard_providers.dart';
import '../../home/domain/dashboard_models.dart';
import '../domain/fire_bucket_allocator.dart';
import '../domain/fire_calculator.dart';
import '../domain/fire_plan.dart';
import '../domain/fire_projection.dart';
import '../domain/fire_review.dart';
import '../domain/fire_review_engine.dart';
import '../domain/fire_state.dart';
import '../domain/fire_state_service.dart';
import '../domain/fire_stress_test.dart';
import '../domain/fire_stress_test_engine.dart';
import 'fire_bucket_rules_preferences.dart';
import 'fire_goal_preferences.dart';
import 'fire_plan_preferences.dart';
import 'fire_review_cache.dart';

/// User's actual annualized return, sourced from the portfolio XIRR engine
/// when the production wiring lands. Keeping it as a stand-alone provider lets
/// the dashboard add a "Live (XIRR)" scenario as soon as the value is
/// non-null — and it stays out of the way (no dotted line, neutral becomes
/// the sensitivity baseline) until then.
///
/// Override at the provider scope or in tests; production wiring will
/// supply a `Provider<double?>` that watches the user's portfolio XIRR
/// across the trailing 1Y window.
final fireLiveAnnualReturnProvider = Provider<double?>((ref) => null);

/// Stateless calculator instance. Cheap to construct so this is mostly for
/// tests — but isolating it lets future PRs swap in a different scenario
/// rate set without touching the dashboard widgets.
final fireCalculatorProvider = Provider<FireCalculator>(
  (ref) => const FireCalculator(),
);

/// The fully-built FIRE dashboard view. Recomputes when the goal,
/// dashboard snapshot (current net worth), or live XIRR rate changes.
///
/// Returns [AsyncValue] so the dashboard can render the dashboard
/// snapshot's loading / error state alongside the FIRE-specific empty
/// state (no goal yet → [FireDashboardView.progressRatio] is null).
final fireDashboardViewProvider = Provider<AsyncValue<FireDashboardView>>((
  ref,
) {
  final goal = ref.watch(fireGoalProvider);
  final snapshotAsync = ref.watch(dashboardSnapshotProvider);
  final liveRate = ref.watch(fireLiveAnnualReturnProvider);
  final calculator = ref.watch(fireCalculatorProvider);
  final baseCurrency = ref.watch(dashboardBaseCurrencyProvider);

  return snapshotAsync.when(
    loading: () => const AsyncValue.loading(),
    error: (e, st) => AsyncValue.error(e, st),
    data: (snapshot) {
      final currentNetWorth = snapshot.isEmpty
          ? Decimal.zero
          : snapshot.netWorth.amount;
      final view = calculator.buildView(
        goal: goal,
        currentNetWorth: currentNetWorth,
        baseCurrency: baseCurrency,
        start: DateTime.now(),
        liveAnnualReturn: liveRate,
      );
      return AsyncValue.data(view);
    },
  );
});

/// Composed [FirePlan] = legacy `FireGoal` fields + FIRE-OS extras +
/// active base currency. Watching this provider gives a single
/// source-of-truth for FIRE planning input across the UI and AI tools.
final firePlanProvider = Provider<FirePlan>((ref) {
  final goal = ref.watch(fireGoalProvider);
  final extras = ref.watch(firePlanExtrasProvider);
  final baseCurrency = ref.watch(dashboardBaseCurrencyProvider);
  return FirePlan.fromGoal(
    goal,
    baseCurrency: baseCurrency,
    safeWithdrawalRate: extras.safeWithdrawalRate,
    targetCashBucketMonths: extras.targetCashBucketMonths,
    lifestyleMode: extras.lifestyleMode,
    reserves: extras.reserves,
    riskSettings: extras.riskSettings,
  );
});

/// Per-role bucket coverage + the assets the allocator couldn't slot.
/// Watches the snapshot, the plan, and the user's bucket rules so the
/// FIRE state and the buckets card stay in sync.
final fireBucketAllocationProvider = Provider<AsyncValue<FireBucketAllocation>>(
  (ref) {
    final plan = ref.watch(firePlanProvider);
    final snapshotAsync = ref.watch(dashboardSnapshotProvider);
    final rules = ref.watch(fireBucketRulesProvider);

    return snapshotAsync.when(
      loading: () => const AsyncValue.loading(),
      error: (e, st) => AsyncValue.error(e, st),
      data: (snapshot) {
        final base = snapshot.baseCurrency;
        final activePlan = plan.baseCurrency == base
            ? plan
            : plan.copyWith(baseCurrency: base);
        return AsyncValue.data(
          allocateBuckets(
            plan: activePlan,
            snapshot: snapshot,
            monthlyExpense: activePlan.monthlyExpenseMoney,
            userRules: rules,
          ),
        );
      },
    );
  },
);

/// The FIRE OS read model. Recomputes whenever the plan, the dashboard
/// snapshot, the trailing cashflow summary, or the projection changes.
final fireStateProvider = Provider<AsyncValue<FireState>>((ref) {
  final plan = ref.watch(firePlanProvider);
  final snapshotAsync = ref.watch(dashboardSnapshotProvider);
  final summaryAsync = ref.watch(
    cashFlowSummaryProvider(
      const CashFlowSummaryRequest(period: CashFlowPeriod.month),
    ),
  );
  final fireView = ref.watch(fireDashboardViewProvider);
  final now = ref.watch(fireNowProvider);

  if (snapshotAsync.isLoading || summaryAsync.isLoading) {
    return const AsyncValue.loading();
  }
  if (snapshotAsync.hasError) {
    return AsyncValue.error(
      snapshotAsync.error!,
      snapshotAsync.stackTrace ?? StackTrace.current,
    );
  }
  if (summaryAsync.hasError) {
    return AsyncValue.error(
      summaryAsync.error!,
      summaryAsync.stackTrace ?? StackTrace.current,
    );
  }

  return snapshotAsync.when(
    loading: () => const AsyncValue.loading(),
    error: (e, st) => AsyncValue.error(e, st),
    data: (snapshot) {
      final base = snapshot.baseCurrency;
      // Defensive: if the plan was persisted under a different base
      // currency (settings switched after onboarding), re-anchor it to
      // the active snapshot currency so the Money arithmetic below
      // never throws `CurrencyMismatchError`.
      final activePlan = plan.baseCurrency == base
          ? plan
          : plan.copyWith(baseCurrency: base);

      final investable = _computeInvestableAssets(snapshot);
      final liquid = _computeLiquidAssets(snapshot);
      final trailing = trailingAnnualSpend(summaryAsync.requireValue, now: now);

      final allocation = ref
          .watch(fireBucketAllocationProvider)
          .maybeWhen(data: (a) => a, orElse: () => null);

      final etaMonths = fireView.whenOrNull(
        data: (view) {
          if (view.scenarios.isEmpty) return null;
          final live = view.scenarios.firstWhereOrNull(
            (s) => s.tier == FireScenarioTier.live,
          );
          final fallback = view.scenarios.firstWhereOrNull(
            (s) => s.tier == FireScenarioTier.neutral,
          );
          return (live ?? fallback ?? view.scenarios.first).monthsToTarget;
        },
      );

      return AsyncValue.data(
        computeFireState(
          plan: activePlan,
          netWorth: snapshot.netWorth,
          investableAssets: investable,
          liquidAssets: liquid,
          trailingAnnualSpend: trailing,
          fireEtaMonths: etaMonths,
          currencyMismatchCount: snapshot.currencyMismatches.length,
          computedAt: now,
          buckets: allocation?.buckets ?? const [],
          unmappedHoldings: allocation?.unmappedHoldings ?? const [],
        ),
      );
    },
  );
});

/// Override-able "now" for the FIRE state engine. Mirrors
/// `cashFlowNowProvider` so tests can pin a deterministic timestamp.
final fireNowProvider = Provider<DateTime>((ref) => DateTime.now().toUtc());

/// Stress-test verdicts for the current [FireState]. Computed in pure
/// dart (no LLM); the AI tool surface in Phase 5 reads this provider
/// directly so explanations stay grounded in deterministic results.
final fireStressTestsProvider = Provider<AsyncValue<List<FireStressResult>>>((
  ref,
) {
  final stateAsync = ref.watch(fireStateProvider);
  return stateAsync.when(
    loading: () => const AsyncValue.loading(),
    error: (e, st) => AsyncValue.error(e, st),
    data: (state) => AsyncValue.data(runStressTests(state)),
  );
});

/// Live periodic review for [kind] derived from the current state +
/// stress tests. Recomputed eagerly when the underlying numbers move
/// so the UI never shows a stale verdict.
final fireLiveReviewProvider =
    Provider.family<AsyncValue<FireReview>, FireReviewKind>((ref, kind) {
      final stateAsync = ref.watch(fireStateProvider);
      final stressAsync = ref.watch(fireStressTestsProvider);
      return stateAsync.when(
        loading: () => const AsyncValue.loading(),
        error: (e, st) => AsyncValue.error(e, st),
        data: (state) {
          final stress = stressAsync.maybeWhen(
            data: (r) => r,
            orElse: () => const <FireStressResult>[],
          );
          return AsyncValue.data(
            generateReview(
              kind: kind,
              state: state,
              stressTests: stress,
              now: ref.watch(fireNowProvider),
            ),
          );
        },
      );
    });

/// Persist the live review for [kind] into [fireReviewCacheProvider].
/// Called by the UI's "Save snapshot" action and by the AI propose
/// pathway once the user confirms a review-update.
Future<void> saveLiveReview(WidgetRef ref, FireReviewKind kind) async {
  final review = ref
      .read(fireLiveReviewProvider(kind))
      .maybeWhen(data: (r) => r, orElse: () => null);
  if (review == null) return;
  await ref.read(fireReviewCacheProvider.notifier).upsert(review);
}

/// Ref-side variant of [saveLiveReview] for AI tool dispatch.
Future<void> saveLiveReviewWithRef(Ref ref, FireReviewKind kind) async {
  final review = ref
      .read(fireLiveReviewProvider(kind))
      .maybeWhen(data: (r) => r, orElse: () => null);
  if (review == null) return;
  await ref.read(fireReviewCacheProvider.notifier).upsert(review);
}

/// Save a full [FirePlan] across the two storage halves: the shared
/// `FireGoal` fields go through [FireGoalController]; the FIRE-OS extras
/// through [FirePlanExtrasController]. AI propose-and-apply (Phase 5)
/// funnels through this helper so the diff that lands matches the diff
/// the user confirmed.
Future<void> saveFirePlan(WidgetRef ref, FirePlan plan) async {
  await ref.read(fireGoalProvider.notifier).save(plan.toGoal());
  await ref
      .read(firePlanExtrasProvider.notifier)
      .save(
        FirePlanExtras(
          safeWithdrawalRate: plan.safeWithdrawalRate,
          targetCashBucketMonths: plan.targetCashBucketMonths,
          lifestyleMode: plan.lifestyleMode,
          reserves: plan.reserves,
          riskSettings: plan.riskSettings,
        ),
      );
}

/// Variant of [saveFirePlan] for code paths that only hold a [Ref]
/// (Riverpod listeners, AI tool dispatch). Has the same semantics.
Future<void> saveFirePlanWithRef(Ref ref, FirePlan plan) async {
  await ref.read(fireGoalProvider.notifier).save(plan.toGoal());
  await ref
      .read(firePlanExtrasProvider.notifier)
      .save(
        FirePlanExtras(
          safeWithdrawalRate: plan.safeWithdrawalRate,
          targetCashBucketMonths: plan.targetCashBucketMonths,
          lifestyleMode: plan.lifestyleMode,
          reserves: plan.reserves,
          riskSettings: plan.riskSettings,
        ),
      );
}

// =====================================================================
//  helpers (testable independently — exported for fire_state tests)
// =====================================================================

/// Liquid + market-traded categories that can actually fund withdrawals.
/// Excludes real estate, vehicles, and (implicitly) liabilities.
Money computeInvestableAssets(DashboardSnapshot snapshot) =>
    _computeInvestableAssets(snapshot);

/// Cash + demand deposits — the cash-bucket math divides by this.
Money computeLiquidAssets(DashboardSnapshot snapshot) =>
    _computeLiquidAssets(snapshot);

Money _computeInvestableAssets(DashboardSnapshot snapshot) {
  var sum = Money.zero(snapshot.baseCurrency);
  for (final a in snapshot.allocations) {
    switch (a.category) {
      case AssetCategory.liability:
      case AssetCategory.realEstate:
      case AssetCategory.vehicle:
        continue;
      case AssetCategory.cash:
      case AssetCategory.stock:
      case AssetCategory.etf:
      case AssetCategory.bondsAndFunds:
      case AssetCategory.crypto:
        sum += a.totalInBase;
    }
  }
  return sum;
}

Money _computeLiquidAssets(DashboardSnapshot snapshot) {
  var sum = Money.zero(snapshot.baseCurrency);
  for (final a in snapshot.allocations) {
    if (a.category == AssetCategory.cash) sum += a.totalInBase;
  }
  return sum;
}

/// Sum trailing-12-month expense buckets out of a monthly [summary] and
/// annualise. Returns `null` when fewer than three months of expense
/// data exist — early-onboarding users would otherwise see a withdrawal
/// rate built on one outlier month.
Money? trailingAnnualSpend(CashFlowSummary summary, {DateTime? now}) {
  if (summary.buckets.isEmpty) return null;
  final nowUtc = (now ?? DateTime.now()).toUtc();

  // Build the rolling 12-month window of `yyyy-MM` keys.
  final windowKeys = <String>{};
  for (var i = 0; i < 12; i++) {
    var y = nowUtc.year;
    var m = nowUtc.month - i;
    while (m < 1) {
      m += 12;
      y -= 1;
    }
    windowKeys.add(
      '${y.toString().padLeft(4, '0')}-${m.toString().padLeft(2, '0')}',
    );
  }

  final observedMonths = <String>{};
  var sum = Decimal.zero;
  for (final bucket in summary.buckets) {
    if (bucket.kind != CashFlowKind.expense) continue;
    if (!windowKeys.contains(bucket.key)) continue;
    observedMonths.add(bucket.key);
    final amt = bucket.totalInBase.amount;
    sum += amt < Decimal.zero ? -amt : amt;
  }

  if (observedMonths.length < 3) return null;
  final monthly = (sum / Decimal.fromInt(observedMonths.length)).toDecimal(
    scaleOnInfinitePrecision: 2,
  );
  final annualised = monthly * Decimal.fromInt(12);
  return Money(annualised, summary.baseCurrency);
}
