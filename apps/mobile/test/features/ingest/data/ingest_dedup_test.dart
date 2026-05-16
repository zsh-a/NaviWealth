import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/local/skills/skills.dart';
import 'package:naviwealth/features/ingest/data/ingest_dedup.dart';
import 'package:naviwealth/features/ingest/domain/ingest_models.dart';

ParsedTransaction _parsed({
  String description = 'Starbucks Coffee',
  int amountMinor = -3800,
  String currency = 'CNY',
  DateTime? at,
}) => ParsedTransaction(
  description: description,
  amountMinor: amountMinor,
  currency: currency,
  occurredAt: at ?? DateTime.utc(2026, 5, 10),
);

TransactionInput _existing({
  String id = 'e1',
  String description = 'Starbucks Coffee',
  String amountMinor = '-3800',
  String currency = 'CNY',
  DateTime? at,
}) => TransactionInput(
  id: id,
  description: description,
  amountMinor: amountMinor,
  currency: currency,
  occurredAt: at ?? DateTime.utc(2026, 5, 10),
);

void main() {
  group('classifyDedup', () {
    test('exact merchant + amount + window → duplicate', () {
      final r = classifyDedup(_parsed(), [_existing()]);
      expect(r.verdict, DedupVerdict.duplicate);
      expect(r.targetEntryId, 'e1');
    });

    test('same amount + same calendar day with empty key → duplicate', () {
      final r = classifyDedup(
        _parsed(description: ''),
        [_existing(description: '')],
      );
      expect(r.verdict, DedupVerdict.duplicate);
    });

    test('same merchant + near amount within tolerance → likely', () {
      final r = classifyDedup(
        _parsed(amountMinor: -3800),
        [_existing(amountMinor: '-3850')],
      );
      expect(r.verdict, DedupVerdict.likelyDuplicate);
      expect(r.targetEntryId, 'e1');
    });

    test('different merchant and amount → newTxn', () {
      final r = classifyDedup(
        _parsed(description: 'Uber Ride', amountMinor: -2200),
        [_existing()],
      );
      expect(r.verdict, DedupVerdict.newTxn);
      expect(r.targetEntryId, isNull);
    });

    test('outside the date window → newTxn', () {
      final r = classifyDedup(
        _parsed(at: DateTime.utc(2026, 5, 20)),
        [_existing(at: DateTime.utc(2026, 5, 10))],
      );
      expect(r.verdict, DedupVerdict.newTxn);
    });

    test('currency mismatch is never a duplicate', () {
      final r = classifyDedup(
        _parsed(currency: 'USD'),
        [_existing(currency: 'CNY')],
      );
      expect(r.verdict, DedupVerdict.newTxn);
    });

    test('zero amount is always fresh', () {
      final r = classifyDedup(_parsed(amountMinor: 0), [_existing()]);
      expect(r.verdict, DedupVerdict.newTxn);
    });
  });
}
