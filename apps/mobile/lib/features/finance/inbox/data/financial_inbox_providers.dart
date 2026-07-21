import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/lifeos/action_outcome.dart';
import '../../../../core/persistence/providers.dart';
import '../../../../core/product/product_metrics.dart';
import '../../../../core/sync/mutation_context.dart';
import '../../../../core/sync/outbox_provider.dart';
import '../../ai_tools/expense_to_transaction_input.dart';
import '../../ai_tools/local_skills/local_skills.dart';
import '../../analytics/data/providers.dart';
import '../../application/read_models/dashboard_providers.dart';
import '../../cashflow/data/dividend_center_providers.dart';
import '../../cashflow/data/dividend_forecast_providers.dart';
import '../../cashflow/domain/dividend_policy_monitor.dart';
import '../../cashflow/domain/dividend_resilience.dart';
import '../../composition/finance_route_paths.dart';
import '../../data/repositories/journal_entry_providers.dart';
import '../../expense/data/expense_anomaly_insight_provider.dart';
import '../../ingest/data/providers.dart';
import '../../investment/data/providers.dart' show holdingsSnapshotProvider;
import '../../life_events/data/financial_decision_providers.dart';
import '../../monthly_close/data/account_reconciliation_providers.dart';
import '../../monthly_close/domain/account_reconciliation.dart';
import '../../rebalance/data/rebalance_providers.dart';
import '../../runway/data/money_runway_providers.dart';
import '../../runway/domain/money_runway.dart';
import '../domain/financial_inbox.dart';
import '../domain/portfolio_guardrail_candidates.dart';
import 'financial_signal_repository.dart';

const _portfolioGuardrails = PortfolioGuardrailCandidates();
const _dividendPolicyMonitor = DividendPolicyMonitor();

final financialInboxNowProvider = Provider<DateTime>((ref) => DateTime.now());

final financialSignalRepositoryProvider =
    FutureProvider<FinancialSignalRepository>((ref) async {
      return FinancialSignalRepository(
        db: await ref.watch(appDatabaseProvider.future),
        outbox: await ref.watch(outboxStoreProvider.future),
        stamper: await ref.watch(mutationStamperProvider.future),
      );
    });

final financialActionOutcomeSummariesProvider = StreamProvider.autoDispose((
  ref,
) async* {
  final repository = await ref.watch(financialSignalRepositoryProvider.future);
  yield* repository.watchActionOutcomes();
});

final financialSignalCandidatesProvider =
    Provider.autoDispose<AsyncValue<List<FinancialSignalCandidate>>>((ref) {
      final pending = ref.watch(pendingIngestReviewItemsProvider);
      return pending.whenData((rows) {
        if (rows.isEmpty) return const <FinancialSignalCandidate>[];
        return <FinancialSignalCandidate>[
          FinancialSignalCandidate(
            sourceKey: 'import-review',
            kind: FinancialInboxKind.importReview,
            priority: FinancialInboxPriority.important,
            count: rows.length,
            route: FinanceRoutes.activityIngest,
          ),
        ];
      });
    });

/// Full deterministic scan used by the Inbox screen itself.
///
/// The Life hub reads [financialInboxProvider], which deliberately keeps its
/// dependency graph small. Opening the Inbox opts into the heavier finance
/// reads, persists their stable signals, and makes them available to the hub
/// on subsequent reads without keeping every domain stream alive globally.
final financialSignalScanCandidatesProvider =
    Provider.autoDispose<AsyncValue<List<FinancialSignalCandidate>>>((ref) {
      final items = <FinancialSignalCandidate>[];
      final now = ref.watch(financialInboxNowProvider);
      final pendingAsync = ref.watch(pendingIngestReviewItemsProvider);
      final runwayAsync = ref.watch(moneyRunwayProvider);
      final reconciliationsAsync = ref.watch(
        reconciliationsForPeriodProvider(_periodKey(now)),
      );
      final expensesAsync = ref.watch(journalExpensesStreamProvider);
      final dashboardAsync = ref.watch(dashboardSnapshotProvider);
      final decisionsAsync = ref.watch(financialDecisionsProvider);
      final concentrationAsync = ref.watch(concentrationAlertsProvider);
      final dividendCenterAsync = ref.watch(dividendCenterSnapshotProvider);
      final holdingsAsync = ref.watch(holdingsSnapshotProvider);
      final declaredDividendActions = ref.watch(
        dividendForecastDeclaredActionsProvider,
      );
      final sources = <AsyncValue<Object?>>[
        pendingAsync,
        runwayAsync,
        reconciliationsAsync,
        expensesAsync,
        dashboardAsync,
        decisionsAsync,
        concentrationAsync,
        dividendCenterAsync,
        holdingsAsync,
      ];
      if (sources.any((source) => source.isLoading)) {
        return const AsyncValue.loading();
      }
      for (final source in sources) {
        if (source.hasError) {
          return AsyncValue.error(source.error!, source.stackTrace!);
        }
      }
      final pending = pendingAsync.requireValue;
      if (pending.isNotEmpty) {
        items.add(
          FinancialSignalCandidate(
            sourceKey: 'import-review',
            kind: FinancialInboxKind.importReview,
            priority: FinancialInboxPriority.important,
            count: pending.length,
            route: FinanceRoutes.activityIngest,
          ),
        );
      }

      final runway = runwayAsync.requireValue;
      if (runway.hasData) {
        if (runway.status != MoneyRunwayStatus.healthy) {
          items.add(
            FinancialSignalCandidate(
              sourceKey: 'runway-risk',
              kind: FinancialInboxKind.runwayRisk,
              priority: runway.status == MoneyRunwayStatus.shortfall
                  ? FinancialInboxPriority.important
                  : FinancialInboxPriority.attention,
              count: 1,
              route: FinanceRoutes.planRunway,
              evidence: runway.toEvidenceJson(),
            ),
          );
        }
        if (runway.missingCurrencies.isNotEmpty) {
          items.add(
            FinancialSignalCandidate(
              sourceKey: 'missing-fx',
              kind: FinancialInboxKind.missingExchangeRate,
              priority: FinancialInboxPriority.attention,
              count: runway.missingCurrencies.length,
              route: FinanceRoutes.planRunway,
              evidence: {
                'currencies': runway.missingCurrencies.toList()..sort(),
              },
            ),
          );
        }
      }

      final reconciliations = reconciliationsAsync.requireValue;
      final mismatches = reconciliations
          .where((row) => row.status == AccountReconciliationStatus.mismatch)
          .toList(growable: false);
      if (mismatches.isNotEmpty) {
        items.add(
          FinancialSignalCandidate(
            sourceKey: 'balance-mismatch:${_periodKey(now)}',
            kind: FinancialInboxKind.balanceMismatch,
            priority: FinancialInboxPriority.important,
            count: mismatches.length,
            route: FinanceRoutes.activityMonthlyClose,
            evidence: <String, Object?>{
              'period': _periodKey(now),
              'mismatch_count': mismatches.length,
            },
          ),
        );
      }

      final anomaly = ref.watch(expenseAnomalyInsightProvider);
      if (anomaly != null) {
        items.add(
          FinancialSignalCandidate(
            sourceKey: 'expense-anomaly:${_periodKey(now)}',
            kind: FinancialInboxKind.expenseAnomaly,
            priority: anomaly.deltaRatio.abs() > 0.5
                ? FinancialInboxPriority.important
                : FinancialInboxPriority.attention,
            count: 1,
            route: FinanceRoutes.expenseReport,
            evidence: <String, Object?>{
              'period': _periodKey(now),
              'delta_ratio': anomaly.deltaRatio,
              'expense_count': anomaly.currentMonthExpenses.length,
              'expenses': [
                for (final expense in anomaly.currentMonthExpenses.take(20))
                  <String, Object?>{
                    'id': expense.id,
                    'date': expense.tradeDate.toUtc().toIso8601String(),
                    'amount': expense.amount.toString(),
                    'currency': expense.currency,
                    if (expense.note?.trim().isNotEmpty ?? false)
                      'note': expense.note!.trim(),
                  },
              ],
            },
          ),
        );
      }

      final expenses = expensesAsync.requireValue;
      final changes = detectSubscriptionChanges(
        expenses.map(expenseToTransactionInput),
      );
      if (changes.isNotEmpty) {
        items.add(
          FinancialSignalCandidate(
            sourceKey: 'subscription-change:${_periodKey(now)}',
            kind: FinancialInboxKind.subscriptionChange,
            priority: FinancialInboxPriority.attention,
            count: changes.length,
            route: FinanceRoutes.expenseReport,
            evidence: <String, Object?>{
              'period': _periodKey(now),
              'change_count': changes.length,
              'max_delta_ratio': changes
                  .map((change) => change.deltaRatio.abs())
                  .reduce((a, b) => a > b ? a : b),
            },
          ),
        );
      }

      final staleHoldingCount = dashboardAsync.requireValue.staleHoldingCount;
      if (staleHoldingCount > 0) {
        items.add(
          FinancialSignalCandidate(
            sourceKey: 'stale-valuations',
            kind: FinancialInboxKind.staleValuation,
            priority: FinancialInboxPriority.attention,
            count: staleHoldingCount,
            route: FinanceRoutes.wealthPortfolio,
            evidence: <String, Object?>{'stale_count': staleHoldingCount},
          ),
        );
      }

      for (final decision in decisionsAsync.requireValue) {
        if (decision.reviewedAt != null || decision.reviewDate.isAfter(now)) {
          continue;
        }
        items.add(
          FinancialSignalCandidate(
            sourceKey: 'decision-review:${decision.id}',
            kind: FinancialInboxKind.decisionReview,
            priority: FinancialInboxPriority.important,
            count: 1,
            route: FinanceRoutes.planLifeEvents,
            evidence: <String, Object?>{
              'template': decision.template.name,
              'review_date': decision.reviewDate.toUtc().toIso8601String(),
            },
          ),
        );
      }

      items.addAll(
        _portfolioGuardrails.fromConcentrationAlerts(
          concentrationAsync.requireValue,
        ),
      );
      // rebalancePlanProvider is sync and may be null while dashboard loads
      // (already gated above via dashboardAsync).
      items.addAll(
        _portfolioGuardrails.fromRebalancePlan(
          ref.watch(rebalancePlanProvider),
        ),
      );

      final heldAssetIds = holdingsAsync.requireValue.keys.toSet();
      final deteriorations = _dividendPolicyMonitor.detect(
        events: dividendCenterAsync.requireValue.events,
        now: now.toUtc(),
        heldAssetIds: heldAssetIds,
      );
      final resilience = const DividendResilienceService().analyze(
        events: dividendCenterAsync.requireValue.events,
        now: now.toUtc(),
        corporateActions: declaredDividendActions,
        excludedEventCount:
            dividendCenterAsync.requireValue.fxExclusions.length,
      );
      items.addAll(
        _portfolioGuardrails.fromDividendDeteriorations(
          deteriorations,
          attributions: {
            for (final row in resilience.attributions) row.assetId: row,
          },
        ),
      );

      return AsyncValue.data(List.unmodifiable(items));
    });

final financialInboxProvider =
    FutureProvider.autoDispose<List<FinancialInboxItem>>((ref) async {
      final repository = await ref.watch(
        financialSignalRepositoryProvider.future,
      );
      final candidates = ref.watch(financialSignalCandidatesProvider);
      if (candidates.isLoading) {
        return repository.listVisible(
          now: ref.watch(financialInboxNowProvider),
        );
      }
      if (candidates.hasError) {
        Error.throwWithStackTrace(candidates.error!, candidates.stackTrace!);
      }
      return repository.detectAll(
        candidates.requireValue,
        now: ref.watch(financialInboxNowProvider),
      );
    });

final financialInboxScanProvider =
    FutureProvider.autoDispose<List<FinancialInboxItem>>((ref) async {
      final repository = await ref.watch(
        financialSignalRepositoryProvider.future,
      );
      final candidates = ref.watch(financialSignalScanCandidatesProvider);
      if (candidates.isLoading) {
        return repository.listVisible(
          now: ref.watch(financialInboxNowProvider),
        );
      }
      if (candidates.hasError) {
        Error.throwWithStackTrace(candidates.error!, candidates.stackTrace!);
      }
      return repository.reconcile(
        candidates.requireValue,
        now: ref.watch(financialInboxNowProvider),
      );
    });

/// Background closure of Finance-owned Execution actions. A complete detector
/// snapshot is required before absence can resolve a signal; loading never
/// becomes an inferred clearance.
final financialSignalRevalidationProvider =
    FutureProvider<FinancialSignalRevalidationReport>((ref) async {
      final closed = ref.watch(lifeClosedActionsProvider);
      if (!closed.hasValue) {
        if (closed.hasError) {
          Error.throwWithStackTrace(closed.error!, closed.stackTrace!);
        }
        return const FinancialSignalRevalidationReport();
      }
      final relevant = closed.requireValue
          .where(
            (action) =>
                action.sourceRowFamily == 'fin:financial_signals' &&
                action.sourceRowId != null,
          )
          .toList(growable: false);
      if (relevant.isEmpty) {
        return const FinancialSignalRevalidationReport();
      }
      final repository = await ref.watch(
        financialSignalRepositoryProvider.future,
      );
      var report = await repository.revalidateClosedActions(
        actions: relevant
            .where((action) => action.status == LifeClosedActionStatus.dropped)
            .toList(growable: false),
        candidates: const <FinancialSignalCandidate>[],
        observedAt: _observationAfter(relevant),
      );
      final completed = relevant
          .where((action) => action.status == LifeClosedActionStatus.done)
          .toList(growable: false);
      if (completed.isNotEmpty) {
        final candidates = ref.watch(financialSignalScanCandidatesProvider);
        if (candidates.isLoading) {
          await _recordRevalidationMetrics(ref, report);
          return report;
        }
        final completedReport = await repository.revalidateClosedActions(
          actions: completed,
          candidates: candidates.hasError ? null : candidates.requireValue,
          observedAt: _observationAfter(completed),
        );
        report = FinancialSignalRevalidationReport(
          actionCompleted:
              report.actionCompleted + completedReport.actionCompleted,
          cleared: report.cleared + completedReport.cleared,
          stillDetected: report.stillDetected + completedReport.stillDetected,
          inconclusive: report.inconclusive + completedReport.inconclusive,
          actionDropped: report.actionDropped + completedReport.actionDropped,
        );
      }
      await _recordRevalidationMetrics(ref, report);
      return report;
    });

DateTime _observationAfter(List<LifeClosedAction> actions) {
  final latest = actions
      .map((action) => action.completedAt.toUtc())
      .reduce((a, b) => a.isAfter(b) ? a : b);
  final now = DateTime.now().toUtc();
  return now.isAfter(latest)
      ? now
      : latest.add(const Duration(microseconds: 1));
}

Future<void> _recordRevalidationMetrics(
  Ref ref,
  FinancialSignalRevalidationReport report,
) async {
  final metrics = ref.read(productMetricsProvider.notifier);
  await metrics.record(
    ProductFunnelEvent.executionActionCompleted,
    success: true,
    quantity: report.actionCompleted,
  );
  await metrics.record(
    ProductFunnelEvent.executionActionDropped,
    success: false,
    quantity: report.actionDropped,
  );
  await metrics.record(
    ProductFunnelEvent.financialSignalRevalidatedCleared,
    success: true,
    quantity: report.cleared,
  );
  await metrics.record(
    ProductFunnelEvent.financialSignalRevalidatedStillActive,
    success: false,
    quantity: report.stillDetected,
  );
  await metrics.record(
    ProductFunnelEvent.financialSignalRevalidationInconclusive,
    success: false,
    quantity: report.inconclusive,
  );
}

String _periodKey(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}';
