/// Executes a [FinanceQueryPlan] against a transaction source.
///
/// The abstract [QueryPlanExecutor] is the seam features can plug a
/// Drift-backed adapter into. The included
/// [InMemoryQueryPlanExecutor] runs against an injected list of
/// [TransactionInput] — sufficient for tests and for the device's
/// 'cached recent transactions' fast path. NetWorthTrendPlan is
/// returned with an empty result by the in-memory executor because
/// net-worth requires the dashboard time series, not transactions.
library;

import '../../contracts/contracts.dart' show DateRange;
import 'finance_query_plan.dart';
import 'merchant_key.dart';
import 'recurring_detector.dart';
import 'refund_matcher.dart';
import 'transaction_input.dart';
import 'txn_classifier.dart';

class QueryRow {
  const QueryRow({required this.label, required this.values});

  final String label;
  final Map<String, Object?> values;
}

class QuerySummary {
  const QuerySummary({
    required this.totalAbsAmountMinor,
    required this.currency,
    this.rowCount,
  });

  /// Total absolute amount in minor units. We sum |amount| because a
  /// 'spending' total with positive net (refunds) is rarely what the
  /// user means.
  final int totalAbsAmountMinor;
  final String currency;
  final int? rowCount;
}

class QueryResult {
  const QueryResult({
    required this.plan,
    required this.rows,
    this.summary,
    this.note,
  });

  final FinanceQueryPlan plan;
  final List<QueryRow> rows;
  final QuerySummary? summary;

  /// Optional human-readable hint for the UI when the result is
  /// degraded ('net worth trend not available offline').
  final String? note;
}

abstract class QueryPlanExecutor {
  Future<QueryResult> run(FinanceQueryPlan plan);
}

class InMemoryQueryPlanExecutor implements QueryPlanExecutor {
  InMemoryQueryPlanExecutor({required this.transactions});

  final List<TransactionInput> transactions;

  @override
  Future<QueryResult> run(FinanceQueryPlan plan) async {
    return switch (plan) {
      final SpendingByCategoryPlan p => _spending(p),
      final TransactionsFilterPlan p => _filter(p),
      final NetWorthTrendPlan p => QueryResult(
        plan: p,
        rows: const <QueryRow>[],
        note:
            'net-worth trend requires the dashboard adapter (not wired in Phase 3-A)',
      ),
      final SubscriptionListPlan p => _subscriptions(p),
      final RefundMatchingPlan p => _refunds(p),
    };
  }

  // ── plan implementations ────────────────────────────────────────

  QueryResult _spending(SpendingByCategoryPlan plan) {
    final inRange = _filterByRange(
      transactions,
      plan.range,
    ).where((t) => parseAmountMinor(t.amountMinor) < 0).toList(growable: false);
    final hintsFilter = plan.categoryHints?.toSet();
    final byCategory = <String, int>{};
    String? currency;
    for (final t in inRange) {
      final classification = classifyTransaction(t);
      final hint = classification?.categoryHint ?? 'uncategorised';
      if (hintsFilter != null && !hintsFilter.contains(hint)) continue;
      currency ??= t.currency;
      if (currency != t.currency) continue; // skip mixed-currency rows
      byCategory[hint] =
          (byCategory[hint] ?? 0) + parseAmountMinor(t.amountMinor).abs();
    }
    final rows =
        byCategory.entries
            .map(
              (e) => QueryRow(
                label: e.key,
                values: <String, Object?>{
                  'category': e.key,
                  'amount_minor': e.value,
                  'currency': currency,
                },
              ),
            )
            .toList(growable: false)
          ..sort(
            (a, b) => (b.values['amount_minor']! as int).compareTo(
              a.values['amount_minor']! as int,
            ),
          );
    final total = byCategory.values.fold<int>(0, (a, b) => a + b);
    return QueryResult(
      plan: plan,
      rows: rows,
      summary: QuerySummary(
        totalAbsAmountMinor: total,
        currency: currency ?? 'USD',
        rowCount: rows.length,
      ),
    );
  }

  QueryResult _filter(TransactionsFilterPlan plan) {
    final hits = <QueryRow>[];
    var total = 0;
    String? currency;
    for (final t in _filterByRange(transactions, plan.range)) {
      if (plan.currency != null && t.currency != plan.currency) continue;
      if (plan.merchantSubstring != null &&
          !merchantKey(
            t.description,
          ).contains(plan.merchantSubstring!.toLowerCase())) {
        continue;
      }
      final amt = parseAmountMinor(t.amountMinor);
      if (plan.minAmountMinor != null && amt < plan.minAmountMinor!) continue;
      if (plan.maxAmountMinor != null && amt > plan.maxAmountMinor!) continue;
      currency ??= t.currency;
      total += amt.abs();
      hits.add(
        QueryRow(
          label: t.description,
          values: <String, Object?>{
            'id': t.id,
            'description': t.description,
            'amount_minor': amt,
            'currency': t.currency,
            'occurred_at': t.occurredAt.toIso8601String(),
          },
        ),
      );
    }
    return QueryResult(
      plan: plan,
      rows: hits,
      summary: QuerySummary(
        totalAbsAmountMinor: total,
        currency: currency ?? plan.currency ?? 'USD',
        rowCount: hits.length,
      ),
    );
  }

  QueryResult _subscriptions(SubscriptionListPlan plan) {
    final scoped = plan.range == null
        ? transactions
        : _filterByRange(transactions, plan.range!).toList(growable: false);
    final patterns = detectRecurring(scoped);
    final rows = patterns
        .map(
          (p) => QueryRow(
            label: p.merchantKey,
            values: <String, Object?>{
              'merchant_key': p.merchantKey,
              'cadence': p.cadence.name,
              'median_amount_minor': p.medianAmountMinor,
              'currency': p.currency,
              'occurrences': p.occurrenceIds.length,
              'last_seen_at': p.lastSeenAt.toIso8601String(),
            },
          ),
        )
        .toList(growable: false);
    return QueryResult(
      plan: plan,
      rows: rows,
      summary: QuerySummary(
        totalAbsAmountMinor: patterns.fold<int>(
          0,
          (acc, p) => acc + p.medianAmountMinor.abs() * p.occurrenceIds.length,
        ),
        currency: patterns.isEmpty ? 'USD' : patterns.first.currency,
        rowCount: rows.length,
      ),
    );
  }

  QueryResult _refunds(RefundMatchingPlan plan) {
    final scoped = _filterByRange(
      transactions,
      plan.range,
    ).toList(growable: false);
    final matches = matchRefunds(scoped);
    final rows = matches
        .map(
          (m) => QueryRow(
            label: '${m.originalTxnId} ↔ ${m.refundTxnId}',
            values: <String, Object?>{
              'original_id': m.originalTxnId,
              'refund_id': m.refundTxnId,
              'amount_minor': m.amountMinor,
              'currency': m.currency,
            },
          ),
        )
        .toList(growable: false);
    return QueryResult(
      plan: plan,
      rows: rows,
      summary: QuerySummary(
        totalAbsAmountMinor: matches.fold<int>(0, (a, m) => a + m.amountMinor),
        currency: matches.isEmpty ? 'USD' : matches.first.currency,
        rowCount: rows.length,
      ),
    );
  }
}

Iterable<TransactionInput> _filterByRange(
  Iterable<TransactionInput> txns,
  DateRange range,
) {
  final from = DateTime.tryParse(range.fromInclusive);
  final to = DateTime.tryParse(range.toExclusive);
  if (from == null || to == null) return txns;
  return txns.where(
    (t) => !t.occurredAt.isBefore(from) && t.occurredAt.isBefore(to),
  );
}
