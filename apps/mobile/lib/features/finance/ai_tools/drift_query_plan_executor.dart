/// Drift-backed [QueryPlanExecutor] adapter.
///
/// The pure logic in [InMemoryQueryPlanExecutor] already does the
/// heavy lifting; we just need a way to source `TransactionInput`
/// values from the live journal. This adapter:
///
///   1. Reads the user's expense rows via `journalExpensesStreamProvider`
///      (one-shot via `.future`).
///   2. Converts each [Expense] to a signed [TransactionInput] (outflow
///      negative — see [expenseToTransactionInput]).
///   3. Delegates to [InMemoryQueryPlanExecutor].
///
/// `NetWorthTrendPlan` is handled here through `dashboardTrendProvider`
/// so the assistant can answer net-worth trend questions from the live dashboard
/// series.
///
/// The adapter is Riverpod-aware so callers can hand in any `Ref` —
/// chat repository, dev page, future natural-language CLI. Tests that
/// want pure logic stay on [InMemoryQueryPlanExecutor] with hand-rolled
/// fixtures.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naviwealth/features/finance/domain/models/expense.dart';
import 'package:naviwealth/features/finance/home/data/dashboard_providers.dart';
import 'package:naviwealth/features/finance/home/domain/dashboard_trend_builder.dart';

import '../data/repositories/journal_entry_providers.dart';
import 'expense_to_transaction_input.dart';
import 'query_plan/finance_query_plan.dart';
import 'query_plan/query_plan_executor.dart';

class DriftQueryPlanExecutor implements QueryPlanExecutor {
  DriftQueryPlanExecutor({required this.ref});

  final Ref ref;

  @override
  Future<QueryResult> run(FinanceQueryPlan plan) async {
    // NetWorthTrendPlan reads from the dashboard trend
    // provider — no transaction list needed.
    if (plan is NetWorthTrendPlan) {
      return _netWorthTrend(plan);
    }
    final expenses = await _readExpensesSafely();
    final txns = expenses
        .map(expenseToTransactionInput)
        .toList(growable: false);
    final inner = InMemoryQueryPlanExecutor(transactions: txns);
    return inner.run(plan);
  }

  Future<QueryResult> _netWorthTrend(NetWorthTrendPlan plan) async {
    final DashboardTrend trend;
    try {
      trend = await ref.read(dashboardTrendProvider.future);
    } catch (e) {
      return QueryResult(
        plan: plan,
        rows: const <QueryRow>[],
        note: 'net-worth trend unavailable: $e',
      );
    }
    final from = DateTime.tryParse(plan.range.fromInclusive);
    final to = DateTime.tryParse(plan.range.toExclusive);
    final points = trend.points
        .where((p) {
          if (from != null && p.asOf.isBefore(from)) return false;
          if (to != null && !p.asOf.isBefore(to)) return false;
          return true;
        })
        .toList(growable: false);
    final rows = points
        .map(
          (p) => QueryRow(
            label: p.asOf.toUtc().toIso8601String(),
            values: <String, Object?>{
              'as_of': p.asOf.toUtc().toIso8601String(),
              'net_worth': p.netWorth.amount.toString(),
              'assets': p.assets.amount.toString(),
              'liabilities': p.liabilities.amount.toString(),
              'currency': trend.baseCurrency,
            },
          ),
        )
        .toList(growable: false);
    return QueryResult(
      plan: plan,
      rows: rows,
      summary: rows.isEmpty
          ? null
          : QuerySummary(
              totalAbsAmountMinor: 0,
              currency: trend.baseCurrency,
              rowCount: rows.length,
            ),
      note: rows.isEmpty ? 'no net-worth samples in requested range' : null,
    );
  }

  Future<List<Expense>> _readExpensesSafely() async {
    try {
      return await ref.read(journalExpensesStreamProvider.future);
    } catch (_) {
      // Producer failure (DB not ready, sync mid-flight) — return
      // empty so the executor produces an honest "no rows" result
      // rather than throwing into the AI surface.
      return const <Expense>[];
    }
  }
}

final driftQueryPlanExecutorProvider = Provider<QueryPlanExecutor>(
  (ref) => DriftQueryPlanExecutor(ref: ref),
);
