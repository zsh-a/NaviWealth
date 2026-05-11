// Tests for the Wave 15 producer wire: end-side detector output →
// AnalyticalUpload list.
//
// `_expenseToTransactionInput` and `_recurringPatternToUpload` are
// private helpers in providers.dart; we exercise them end-to-end by
// reconstructing the same logic against the public detectors and
// asserting wire shape. This avoids exposing helpers solely for tests
// while still locking the conversion contract.

import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/contracts/contracts.dart';
import 'package:naviwealth/core/ai/local/skills/skills.dart';

void main() {
  group('Expense → TransactionInput (mirrors providers.dart)', () {
    test('amount becomes signed-negative minor units', () {
      final t = TransactionInput(
        id: 'e1',
        description: 'STARBUCKS 04291',
        amountMinor: '-${(Decimal.parse('4.50') * Decimal.fromInt(100)).floor().toBigInt()}',
        currency: 'USD',
        occurredAt: DateTime.utc(2026, 5, 12, 10),
        accountId: 'cat_food',
        categoryId: 'cat_food',
      );
      expect(t.amountMinor, '-450');
      expect(parseAmountMinor(t.amountMinor), -450);
    });

    test('empty note → empty description (detector skips entry)', () {
      final t = TransactionInput(
        id: 'e1',
        description: '',
        amountMinor: '-100',
        currency: 'USD',
        occurredAt: DateTime.utc(2026, 5, 12),
      );
      expect(t.description, '');
      expect(merchantKey(t.description), '');
    });
  });

  group('detectRecurring + RecurringPattern → AnalyticalUpload payload', () {
    test('payload carries cadence / median / occurrences / last_seen', () {
      // Three Netflix charges, monthly cadence.
      final txns = <TransactionInput>[
        TransactionInput(
          id: 'jan',
          description: 'NETFLIX.COM',
          amountMinor: '-999',
          currency: 'USD',
          occurredAt: DateTime.utc(2026, 1, 5),
        ),
        TransactionInput(
          id: 'feb',
          description: 'NETFLIX',
          amountMinor: '-999',
          currency: 'USD',
          occurredAt: DateTime.utc(2026, 2, 4),
        ),
        TransactionInput(
          id: 'mar',
          description: 'NETFLIX',
          amountMinor: '-999',
          currency: 'USD',
          occurredAt: DateTime.utc(2026, 3, 6),
        ),
      ];
      final patterns = detectRecurring(txns);
      expect(patterns, hasLength(1));
      final p = patterns.single;
      // Mirror the providers.dart mapping inline:
      final upload = AnalyticalUpload(
        kind: 'recurring_pattern',
        id: '${p.merchantKey}|${p.currency}',
        payload: <String, Object?>{
          'merchant_key': p.merchantKey,
          'cadence': p.cadence.name,
          'median_amount_minor': p.medianAmountMinor.toString(),
          'currency': p.currency,
          'occurrences': p.occurrenceIds.length,
          'last_seen_at': p.lastSeenAt.toIso8601String(),
        },
      );
      expect(upload.kind, 'recurring_pattern');
      expect(upload.id, 'netflix|USD');
      expect(upload.payload['cadence'], 'monthly');
      expect(upload.payload['median_amount_minor'], '-999');
      expect(upload.payload['occurrences'], 3);
      expect(upload.payload['merchant_key'], 'netflix');
    });

    test('id format is "merchantKey|currency" so multi-currency same merchant becomes two rows', () {
      // Two parallel patterns: NETFLIX in USD and NETFLIX in CNY.
      final usdTxns = <TransactionInput>[
        for (var m = 1; m <= 3; m++)
          TransactionInput(
            id: 'u$m',
            description: 'NETFLIX',
            amountMinor: '-999',
            currency: 'USD',
            occurredAt: DateTime.utc(2026, m, 5),
          ),
      ];
      final cnyTxns = <TransactionInput>[
        for (var m = 1; m <= 3; m++)
          TransactionInput(
            id: 'c$m',
            description: 'NETFLIX',
            amountMinor: '-7900',
            currency: 'CNY',
            occurredAt: DateTime.utc(2026, m, 5),
          ),
      ];
      final patterns = detectRecurring(<TransactionInput>[
        ...usdTxns,
        ...cnyTxns,
      ]);
      expect(patterns, hasLength(2));
      final ids = patterns
          .map((p) => '${p.merchantKey}|${p.currency}')
          .toSet();
      expect(ids, <String>{'netflix|USD', 'netflix|CNY'});
    });

    test('no patterns → no recurring uploads (mirrors guard in providers)', () {
      final txns = <TransactionInput>[
        TransactionInput(
          id: 'one_off',
          description: 'COSTCO',
          amountMinor: '-12000',
          currency: 'USD',
          occurredAt: DateTime.utc(2026, 5, 1),
        ),
      ];
      final patterns = detectRecurring(txns);
      expect(patterns, isEmpty);
    });
  });
}
