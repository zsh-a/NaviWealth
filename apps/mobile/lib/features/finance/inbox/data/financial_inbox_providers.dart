import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/persistence/providers.dart';
import '../../../../core/sync/mutation_context.dart';
import '../../../../core/sync/outbox_provider.dart';
import '../../ai_tools/expense_to_transaction_input.dart';
import '../../ai_tools/local_skills/local_skills.dart';
import '../../application/read_models/dashboard_providers.dart';
import '../../composition/finance_route_paths.dart';
import '../../data/repositories/journal_entry_providers.dart';
import '../../expense/data/expense_anomaly_insight_provider.dart';
import '../../ingest/data/providers.dart';
import '../../life_events/data/financial_decision_providers.dart';
import '../../monthly_close/data/account_reconciliation_providers.dart';
import '../../monthly_close/domain/account_reconciliation.dart';
import '../../runway/data/money_runway_providers.dart';
import '../../runway/domain/money_runway.dart';
import '../domain/financial_inbox.dart';
import 'financial_signal_repository.dart';

final financialInboxNowProvider = Provider<DateTime>((ref) => DateTime.now());

final financialSignalRepositoryProvider =
    FutureProvider<FinancialSignalRepository>((ref) async {
      return FinancialSignalRepository(
        db: await ref.watch(appDatabaseProvider.future),
        outbox: await ref.watch(outboxStoreProvider.future),
        stamper: await ref.watch(mutationStamperProvider.future),
      );
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
      final sources = <AsyncValue<Object?>>[
        pendingAsync,
        runwayAsync,
        reconciliationsAsync,
        expensesAsync,
        dashboardAsync,
        decisionsAsync,
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

String _periodKey(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}';
