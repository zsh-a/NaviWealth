import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/local/skills/skills.dart';

void main() {
  group('matchTransfers', () {
    test('matches outflow + inflow on different accounts within window', () {
      final matches = matchTransfers(<TransactionInput>[
        TransactionInput(
          id: 'out',
          description: 'INTERNAL XFER OUT',
          amountMinor: '-100000',
          currency: 'USD',
          occurredAt: DateTime.utc(2026, 5, 10, 10),
          accountId: 'acc_checking',
        ),
        TransactionInput(
          id: 'in',
          description: 'INTERNAL XFER IN',
          amountMinor: '100000',
          currency: 'USD',
          occurredAt: DateTime.utc(2026, 5, 10, 12),
          accountId: 'acc_savings',
        ),
      ]);
      expect(matches, hasLength(1));
      final m = matches.single;
      expect(m.fromTxnId, 'out');
      expect(m.toTxnId, 'in');
      expect(m.amountMinor, 100000);
    });

    test('does not pair same-account entries', () {
      final matches = matchTransfers(<TransactionInput>[
        TransactionInput(
          id: 'a',
          description: 'CORRECTION',
          amountMinor: '-5000',
          currency: 'USD',
          occurredAt: DateTime.utc(2026, 5, 10),
          accountId: 'acc',
        ),
        TransactionInput(
          id: 'b',
          description: 'CORRECTION',
          amountMinor: '5000',
          currency: 'USD',
          occurredAt: DateTime.utc(2026, 5, 10),
          accountId: 'acc',
        ),
      ]);
      expect(matches, isEmpty);
    });

    test('does not cross currency boundaries', () {
      final matches = matchTransfers(<TransactionInput>[
        TransactionInput(
          id: 'usd',
          description: 'WIRE',
          amountMinor: '-100000',
          currency: 'USD',
          occurredAt: DateTime.utc(2026, 5, 10),
          accountId: 'a',
        ),
        TransactionInput(
          id: 'cny',
          description: 'WIRE',
          amountMinor: '100000',
          currency: 'CNY',
          occurredAt: DateTime.utc(2026, 5, 10),
          accountId: 'b',
        ),
      ]);
      expect(matches, isEmpty);
    });

    test('skips pairs more than 2 days apart', () {
      final matches = matchTransfers(<TransactionInput>[
        TransactionInput(
          id: 'out',
          description: 'XFER',
          amountMinor: '-1000',
          currency: 'USD',
          occurredAt: DateTime.utc(2026, 5, 1),
          accountId: 'a',
        ),
        TransactionInput(
          id: 'in',
          description: 'XFER',
          amountMinor: '1000',
          currency: 'USD',
          occurredAt: DateTime.utc(2026, 5, 6),
          accountId: 'b',
        ),
      ]);
      expect(matches, isEmpty);
    });

    test('tolerates small fee shave on the receiving side', () {
      final matches = matchTransfers(<TransactionInput>[
        TransactionInput(
          id: 'out',
          description: 'XFER',
          amountMinor: '-100000',
          currency: 'USD',
          occurredAt: DateTime.utc(2026, 5, 10),
          accountId: 'a',
        ),
        TransactionInput(
          id: 'in',
          description: 'XFER',
          amountMinor: '99975',
          currency: 'USD',
          occurredAt: DateTime.utc(2026, 5, 10),
          accountId: 'b',
        ),
      ]);
      expect(matches, hasLength(1));
    });

    test('does not double-consume the same transaction', () {
      final matches = matchTransfers(<TransactionInput>[
        TransactionInput(
          id: 'out',
          description: 'XFER',
          amountMinor: '-1000',
          currency: 'USD',
          occurredAt: DateTime.utc(2026, 5, 10),
          accountId: 'a',
        ),
        TransactionInput(
          id: 'in_1',
          description: 'XFER',
          amountMinor: '1000',
          currency: 'USD',
          occurredAt: DateTime.utc(2026, 5, 10),
          accountId: 'b',
        ),
        TransactionInput(
          id: 'in_2',
          description: 'XFER',
          amountMinor: '1000',
          currency: 'USD',
          occurredAt: DateTime.utc(2026, 5, 10),
          accountId: 'b',
        ),
      ]);
      // Only one inflow can match the single outflow.
      expect(matches, hasLength(1));
    });
  });
}
