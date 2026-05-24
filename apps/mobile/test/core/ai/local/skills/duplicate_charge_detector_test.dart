import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/local/skills/duplicate_charge_detector.dart';
import 'package:naviwealth/core/ai/local/skills/transaction_input.dart';

TransactionInput _t({
  required String id,
  required String description,
  required int signedMinor,
  String currency = 'CNY',
  required DateTime occurredAt,
}) => TransactionInput(
  id: id,
  description: description,
  amountMinor: signedMinor.toString(),
  currency: currency,
  occurredAt: occurredAt,
);

void main() {
  group('detectDuplicateCharges', () {
    test('flags same-merchant same-amount within 2 days', () {
      final txns = <TransactionInput>[
        _t(
          id: 'a',
          description: 'Starbucks #4521',
          signedMinor: -4500,
          occurredAt: DateTime.utc(2026, 5, 10, 9),
        ),
        _t(
          id: 'b',
          description: 'Starbucks #4521',
          signedMinor: -4500,
          occurredAt: DateTime.utc(2026, 5, 11, 9),
        ),
      ];
      final out = detectDuplicateCharges(txns);
      expect(out, hasLength(1));
      expect(out.first.firstTxnId, 'a');
      expect(out.first.secondTxnId, 'b');
      expect(out.first.amountMinor, 4500);
      expect(out.first.gapDays, 1);
    });

    test('skips pairs more than 2 days apart', () {
      final txns = <TransactionInput>[
        _t(
          id: 'a',
          description: 'Starbucks',
          signedMinor: -4500,
          occurredAt: DateTime.utc(2026, 5, 10, 9),
        ),
        _t(
          id: 'b',
          description: 'Starbucks',
          signedMinor: -4500,
          occurredAt: DateTime.utc(2026, 5, 14, 9),
        ),
      ];
      expect(detectDuplicateCharges(txns), isEmpty);
    });

    test('skips pairs whose amounts differ', () {
      final txns = <TransactionInput>[
        _t(
          id: 'a',
          description: 'Starbucks',
          signedMinor: -4500,
          occurredAt: DateTime.utc(2026, 5, 10),
        ),
        _t(
          id: 'b',
          description: 'Starbucks',
          signedMinor: -4600,
          occurredAt: DateTime.utc(2026, 5, 11),
        ),
      ];
      expect(detectDuplicateCharges(txns), isEmpty);
    });

    test('excludes pairs already explained by a refund match', () {
      final txns = <TransactionInput>[
        // Original purchase + refund within the standard refund window —
        // the pair-scan should not also call them a duplicate charge.
        _t(
          id: 'orig',
          description: 'Amazon order',
          signedMinor: -7900,
          occurredAt: DateTime.utc(2026, 5, 10),
        ),
        _t(
          id: 'refund',
          description: 'Amazon order',
          signedMinor: 7900,
          occurredAt: DateTime.utc(2026, 5, 11),
        ),
      ];
      expect(detectDuplicateCharges(txns), isEmpty);
    });

    test('does not pair across different merchants', () {
      final txns = <TransactionInput>[
        _t(
          id: 'a',
          description: 'Starbucks',
          signedMinor: -4500,
          occurredAt: DateTime.utc(2026, 5, 10),
        ),
        _t(
          id: 'b',
          description: 'Blue Bottle',
          signedMinor: -4500,
          occurredAt: DateTime.utc(2026, 5, 11),
        ),
      ];
      expect(detectDuplicateCharges(txns), isEmpty);
    });

    test('does not double-consume a transaction across pairs', () {
      // Three charges in a row — the detector should pair only (a,b),
      // leaving c unpaired (it would have to back-track to find a
      // pairing with b which is already consumed).
      final txns = <TransactionInput>[
        _t(
          id: 'a',
          description: 'Cafe',
          signedMinor: -2000,
          occurredAt: DateTime.utc(2026, 5, 10),
        ),
        _t(
          id: 'b',
          description: 'Cafe',
          signedMinor: -2000,
          occurredAt: DateTime.utc(2026, 5, 10, 12),
        ),
        _t(
          id: 'c',
          description: 'Cafe',
          signedMinor: -2000,
          occurredAt: DateTime.utc(2026, 5, 11),
        ),
      ];
      final out = detectDuplicateCharges(txns);
      expect(out, hasLength(1));
      expect(out.first.firstTxnId, 'a');
      expect(out.first.secondTxnId, 'b');
    });
  });
}
