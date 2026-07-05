import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/ai_tools/local_skills/local_skills.dart';

void main() {
  group('matchRefunds', () {
    test('matches purchase with same-merchant later credit', () {
      final matches = matchRefunds(<TransactionInput>[
        TransactionInput(
          id: 'orig',
          description: 'AMAZON.COM*ABC',
          amountMinor: '-12500',
          currency: 'USD',
          occurredAt: DateTime.utc(2026, 5, 1),
        ),
        TransactionInput(
          id: 'refund',
          description: 'AMAZON REFUND XYZ',
          amountMinor: '12500',
          currency: 'USD',
          occurredAt: DateTime.utc(2026, 5, 8),
        ),
      ]);
      expect(matches, hasLength(1));
      expect(matches.single.originalTxnId, 'orig');
      expect(matches.single.refundTxnId, 'refund');
    });

    test('does not match when refund precedes the original', () {
      final matches = matchRefunds(<TransactionInput>[
        TransactionInput(
          id: 'credit_first',
          description: 'AMAZON',
          amountMinor: '5000',
          currency: 'USD',
          occurredAt: DateTime.utc(2026, 5, 1),
        ),
        TransactionInput(
          id: 'orig',
          description: 'AMAZON',
          amountMinor: '-5000',
          currency: 'USD',
          occurredAt: DateTime.utc(2026, 5, 5),
        ),
      ]);
      expect(matches, isEmpty);
    });

    test('does not match across merchants', () {
      final matches = matchRefunds(<TransactionInput>[
        TransactionInput(
          id: 'orig',
          description: 'BESTBUY',
          amountMinor: '-15000',
          currency: 'USD',
          occurredAt: DateTime.utc(2026, 5, 1),
        ),
        TransactionInput(
          id: 'unrelated',
          description: 'AMAZON',
          amountMinor: '15000',
          currency: 'USD',
          occurredAt: DateTime.utc(2026, 5, 2),
        ),
      ]);
      expect(matches, isEmpty);
    });

    test('skips refunds older than the 30-day window', () {
      final matches = matchRefunds(<TransactionInput>[
        TransactionInput(
          id: 'orig',
          description: 'STORE',
          amountMinor: '-9900',
          currency: 'USD',
          occurredAt: DateTime.utc(2026, 4, 1),
        ),
        TransactionInput(
          id: 'late',
          description: 'STORE',
          amountMinor: '9900',
          currency: 'USD',
          occurredAt: DateTime.utc(2026, 5, 5),
        ),
      ]);
      expect(matches, isEmpty);
    });

    test('matches partial refunds within tolerance', () {
      final matches = matchRefunds(<TransactionInput>[
        TransactionInput(
          id: 'orig',
          description: 'STORE',
          amountMinor: '-100000',
          currency: 'USD',
          occurredAt: DateTime.utc(2026, 5, 1),
        ),
        TransactionInput(
          id: 'partial',
          // 99,500 is within 1% of 100,000.
          description: 'STORE',
          amountMinor: '99500',
          currency: 'USD',
          occurredAt: DateTime.utc(2026, 5, 5),
        ),
      ]);
      expect(matches, hasLength(1));
    });

    test('one refund matches one original (no double-pairing)', () {
      final matches = matchRefunds(<TransactionInput>[
        TransactionInput(
          id: 'orig_a',
          description: 'STORE',
          amountMinor: '-5000',
          currency: 'USD',
          occurredAt: DateTime.utc(2026, 5, 1),
        ),
        TransactionInput(
          id: 'orig_b',
          description: 'STORE',
          amountMinor: '-5000',
          currency: 'USD',
          occurredAt: DateTime.utc(2026, 5, 2),
        ),
        TransactionInput(
          id: 'refund_a',
          description: 'STORE',
          amountMinor: '5000',
          currency: 'USD',
          occurredAt: DateTime.utc(2026, 5, 7),
        ),
      ]);
      expect(matches, hasLength(1));
      expect(matches.single.originalTxnId, 'orig_a');
      expect(matches.single.refundTxnId, 'refund_a');
    });
  });
}
