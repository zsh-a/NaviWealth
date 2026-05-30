import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/local/skills/skills.dart';

void main() {
  group('classifyTransaction', () {
    test('classifies a known coffee merchant with high confidence', () {
      final c = classifyTransaction(
        TransactionInput(
          id: 't1',
          description: 'STARBUCKS 04291',
          amountMinor: '-450',
          currency: 'USD',
          occurredAt: DateTime.utc(2026, 5, 1),
        ),
      );
      expect(c, isNotNull);
      expect(c!.categoryHint, 'coffee');
      expect(c.confidence, 0.9);
      expect(c.reason, contains('starbucks'));
    });

    test('classifies a Chinese merchant', () {
      final c = classifyTransaction(
        TransactionInput(
          id: 't2',
          description: '美团外卖 -订单 #abc',
          amountMinor: '-3500',
          currency: 'CNY',
          occurredAt: DateTime.utc(2026, 5, 1),
        ),
      );
      expect(c?.categoryHint, 'food_delivery');
    });

    test('uses full descriptor so multi-word merchants match', () {
      final c = classifyTransaction(
        TransactionInput(
          id: 't-blue',
          description: 'Blue Bottle Coffee',
          amountMinor: '-650',
          currency: 'USD',
          occurredAt: DateTime.utc(2026, 5, 1),
        ),
      );
      expect(c?.categoryHint, 'coffee');
    });

    test('prefers specific food delivery over broad transport merchant', () {
      final eats = classifyTransaction(
        TransactionInput(
          id: 't-eats',
          description: 'UBER * EATS',
          amountMinor: '-2100',
          currency: 'USD',
          occurredAt: DateTime.utc(2026, 5, 1),
        ),
      );
      final ride = classifyTransaction(
        TransactionInput(
          id: 't-ride',
          description: 'UBER TRIP',
          amountMinor: '-1800',
          currency: 'USD',
          occurredAt: DateTime.utc(2026, 5, 1),
        ),
      );
      expect(eats?.categoryHint, 'food_delivery');
      expect(ride?.categoryHint, 'transport');
    });

    test('disambiguates Apple Store from Apple Music', () {
      final store = classifyTransaction(
        TransactionInput(
          id: 't-store',
          description: 'Apple Store',
          amountMinor: '-129900',
          currency: 'USD',
          occurredAt: DateTime.utc(2026, 5, 1),
        ),
      );
      final music = classifyTransaction(
        TransactionInput(
          id: 't-music',
          description: 'Apple Music',
          amountMinor: '-1099',
          currency: 'USD',
          occurredAt: DateTime.utc(2026, 5, 1),
        ),
      );
      expect(store?.categoryHint, 'shopping');
      expect(music?.categoryHint, 'subscription');
    });

    test('returns null when merchant is unknown', () {
      final c = classifyTransaction(
        TransactionInput(
          id: 't3',
          description: 'Bob\'s Plumbing',
          amountMinor: '-25000',
          currency: 'USD',
          occurredAt: DateTime.utc(2026, 5, 1),
        ),
      );
      expect(c, isNull);
    });

    test('returns null when transaction already has a category', () {
      final c = classifyTransaction(
        TransactionInput(
          id: 't4',
          description: 'STARBUCKS 04291',
          amountMinor: '-450',
          currency: 'USD',
          occurredAt: DateTime.utc(2026, 5, 1),
          categoryId: 'cat_existing',
        ),
      );
      expect(c, isNull);
    });

    test('returns null for inflows', () {
      final c = classifyTransaction(
        TransactionInput(
          id: 't-income',
          description: 'STARBUCKS REFUND',
          amountMinor: '450',
          currency: 'USD',
          occurredAt: DateTime.utc(2026, 5, 1),
        ),
      );
      expect(c, isNull);
    });

    test('returns null when description has no letters', () {
      final c = classifyTransaction(
        TransactionInput(
          id: 't5',
          description: '12345',
          amountMinor: '-100',
          currency: 'USD',
          occurredAt: DateTime.utc(2026, 5, 1),
        ),
      );
      expect(c, isNull);
    });
  });
}
