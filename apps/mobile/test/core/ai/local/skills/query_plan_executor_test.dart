import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/contracts/contracts.dart' show DateRange;
import 'package:naviwealth/core/ai/local/skills/skills.dart';

void main() {
  group('InMemoryQueryPlanExecutor — SpendingByCategoryPlan', () {
    test('totals by category, filtered by hint', () async {
      final exec = InMemoryQueryPlanExecutor(
        transactions: <TransactionInput>[
          _txn('STARBUCKS 1', -450, '2026-04-15'),
          _txn('STARBUCKS 2', -550, '2026-04-20'),
          _txn('NETFLIX', -999, '2026-04-22'),
          _txn('UBER', -1500, '2026-04-25'),
        ],
      );
      final result = await exec.run(
        const SpendingByCategoryPlan(
          range: DateRange(
            fromInclusive: '2026-04-01T00:00:00.000Z',
            toExclusive: '2026-05-01T00:00:00.000Z',
          ),
          categoryHints: <String>['coffee'],
        ),
      );
      expect(result.rows, hasLength(1));
      expect(result.rows.single.values['category'], 'coffee');
      expect(result.rows.single.values['amount_minor'], 1000);
      expect(result.summary?.totalAbsAmountMinor, 1000);
    });

    test('without hints returns full breakdown sorted desc', () async {
      final exec = InMemoryQueryPlanExecutor(
        transactions: <TransactionInput>[
          _txn('STARBUCKS', -500, '2026-04-15'),
          _txn('UBER', -2500, '2026-04-20'),
          _txn('NETFLIX', -999, '2026-04-22'),
        ],
      );
      final result = await exec.run(
        const SpendingByCategoryPlan(
          range: DateRange(
            fromInclusive: '2026-04-01T00:00:00.000Z',
            toExclusive: '2026-05-01T00:00:00.000Z',
          ),
        ),
      );
      // Sort: transport (2500), subscription (999), coffee (500).
      expect(result.rows.map((r) => r.values['category']).toList(), <String>[
        'transport',
        'subscription',
        'coffee',
      ]);
    });

    test('inflows are excluded from spending totals', () async {
      final exec = InMemoryQueryPlanExecutor(
        transactions: <TransactionInput>[
          _txn('STARBUCKS', -500, '2026-04-15'),
          _txn('REFUND', 500, '2026-04-20'), // positive, not a spend
        ],
      );
      final result = await exec.run(
        const SpendingByCategoryPlan(
          range: DateRange(
            fromInclusive: '2026-04-01T00:00:00.000Z',
            toExclusive: '2026-05-01T00:00:00.000Z',
          ),
        ),
      );
      expect(result.summary?.totalAbsAmountMinor, 500);
    });

    test(
      'can refine existing broad ledger category from description',
      () async {
        final exec = InMemoryQueryPlanExecutor(
          transactions: <TransactionInput>[
            _txn(
              'STARBUCKS',
              -500,
              '2026-04-15',
              categoryId: 'system-account:u1:expense:food',
            ),
            _txn(
              'Unknown Cafe',
              -800,
              '2026-04-16',
              categoryId: 'system-account:u1:expense:food',
            ),
          ],
        );
        final result = await exec.run(
          const SpendingByCategoryPlan(
            range: DateRange(
              fromInclusive: '2026-04-01T00:00:00.000Z',
              toExclusive: '2026-05-01T00:00:00.000Z',
            ),
          ),
        );
        expect(result.rows.map((r) => r.values['category']).toList(), <String>[
          'food',
          'coffee',
        ]);
      },
    );
  });

  group('InMemoryQueryPlanExecutor — TransactionsFilterPlan', () {
    test('returns matching transactions in arrival order', () async {
      final exec = InMemoryQueryPlanExecutor(
        transactions: <TransactionInput>[
          _txn('STARBUCKS', -500, '2026-04-15'),
          _txn('UBER', -2500, '2026-04-20'),
          _txn('NETFLIX', -999, '2026-05-22'),
        ],
      );
      final result = await exec.run(
        const TransactionsFilterPlan(
          range: DateRange(
            fromInclusive: '2026-04-01T00:00:00.000Z',
            toExclusive: '2026-05-01T00:00:00.000Z',
          ),
          merchantSubstring: 'star',
        ),
      );
      expect(result.rows, hasLength(1));
      expect(result.rows.single.values['description'], 'STARBUCKS');
    });

    test('respects amount bounds', () async {
      final exec = InMemoryQueryPlanExecutor(
        transactions: <TransactionInput>[
          _txn('A', -100, '2026-04-15'),
          _txn('B', -1000, '2026-04-16'),
          _txn('C', -10000, '2026-04-17'),
        ],
      );
      final result = await exec.run(
        const TransactionsFilterPlan(
          range: DateRange(
            fromInclusive: '2026-04-01T00:00:00.000Z',
            toExclusive: '2026-05-01T00:00:00.000Z',
          ),
          minAmountMinor: -5000, // exclude C (-10000 < -5000)
          maxAmountMinor: -200, // exclude A (-100 > -200)
        ),
      );
      expect(result.rows.map((r) => r.values['description']).toList(), <String>[
        'B',
      ]);
    });
  });

  group('InMemoryQueryPlanExecutor — SubscriptionListPlan', () {
    test('lifts recurring patterns into rows', () async {
      final exec = InMemoryQueryPlanExecutor(
        transactions: <TransactionInput>[
          _txn('NETFLIX', -999, '2026-01-05'),
          _txn('NETFLIX', -999, '2026-02-04'),
          _txn('NETFLIX', -999, '2026-03-06'),
        ],
      );
      final result = await exec.run(const SubscriptionListPlan());
      expect(result.rows, hasLength(1));
      expect(result.rows.single.values['merchant_key'], 'netflix');
      expect(result.rows.single.values['cadence'], 'monthly');
      expect(result.rows.single.values['occurrences'], 3);
    });
  });

  group('InMemoryQueryPlanExecutor — RefundMatchingPlan', () {
    test('matches purchase + later refund', () async {
      final exec = InMemoryQueryPlanExecutor(
        transactions: <TransactionInput>[
          _txn('AMAZON', -12500, '2026-05-01'),
          _txn('AMAZON', 12500, '2026-05-08'),
        ],
      );
      final result = await exec.run(
        const RefundMatchingPlan(
          range: DateRange(
            fromInclusive: '2026-05-01T00:00:00.000Z',
            toExclusive: '2026-06-01T00:00:00.000Z',
          ),
        ),
      );
      expect(result.rows, hasLength(1));
      expect(result.rows.single.values['amount_minor'], 12500);
    });
  });

  group('InMemoryQueryPlanExecutor — NetWorthTrendPlan', () {
    test('returns empty result with a degraded note', () async {
      final exec = InMemoryQueryPlanExecutor(
        transactions: const <TransactionInput>[],
      );
      final result = await exec.run(
        const NetWorthTrendPlan(
          range: DateRange(
            fromInclusive: '2026-01-01T00:00:00.000Z',
            toExclusive: '2026-05-01T00:00:00.000Z',
          ),
        ),
      );
      expect(result.rows, isEmpty);
      expect(result.note, contains('net-worth'));
    });
  });
}

TransactionInput _txn(
  String desc,
  int amountMinor,
  String date, {
  String? categoryId,
}) {
  // `date` is an ISO calendar date (YYYY-MM-DD); we always anchor it
  // to UTC midnight so range comparisons against ContextPack-style
  // ISO ranges are timezone-independent.
  final parts = date.split('-');
  return TransactionInput(
    id: '${desc}_$date',
    description: desc,
    amountMinor: amountMinor.toString(),
    currency: 'USD',
    categoryId: categoryId,
    occurredAt: DateTime.utc(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    ),
  );
}
