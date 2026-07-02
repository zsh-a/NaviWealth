import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/ai_tools/local_skills/local_skills.dart';

void main() {
  TransactionInput netflix(int day, {int amount = -999}) => TransactionInput(
    id: 'n_$day',
    description: 'NETFLIX.COM',
    amountMinor: amount.toString(),
    currency: 'USD',
    occurredAt: DateTime.utc(2026, 1, day),
  );

  group('detectRecurring — monthly cadence', () {
    test('three monthly Netflix charges → detected', () {
      final patterns = detectRecurring(<TransactionInput>[
        netflix(5),
        TransactionInput(
          id: 'n_2',
          description: 'NETFLIX',
          amountMinor: '-999',
          currency: 'USD',
          occurredAt: DateTime.utc(2026, 2, 4),
        ),
        TransactionInput(
          id: 'n_3',
          description: 'NETFLIX',
          amountMinor: '-999',
          currency: 'USD',
          occurredAt: DateTime.utc(2026, 3, 6),
        ),
      ]);
      expect(patterns, hasLength(1));
      final p = patterns.single;
      expect(p.merchantKey, 'netflix');
      expect(p.cadence, RecurringCadence.monthly);
      expect(p.medianAmountMinor, -999);
      expect(p.occurrenceIds, hasLength(3));
    });

    test('two occurrences → not detected (need 3+)', () {
      final patterns = detectRecurring(<TransactionInput>[
        netflix(5),
        TransactionInput(
          id: 'n_2',
          description: 'NETFLIX',
          amountMinor: '-999',
          currency: 'USD',
          occurredAt: DateTime.utc(2026, 2, 4),
        ),
      ]);
      expect(patterns, isEmpty);
    });

    test('irregular intervals → not detected', () {
      final patterns = detectRecurring(<TransactionInput>[
        netflix(5),
        TransactionInput(
          id: 'n_2',
          description: 'NETFLIX',
          amountMinor: '-999',
          currency: 'USD',
          occurredAt: DateTime.utc(2026, 1, 20), // ~15 days
        ),
        TransactionInput(
          id: 'n_3',
          description: 'NETFLIX',
          amountMinor: '-999',
          currency: 'USD',
          occurredAt: DateTime.utc(2026, 2, 19),
        ),
      ]);
      expect(patterns, isEmpty);
    });

    test('a tail-end amount outlier is filtered, leaving the steady run', () {
      // Three steady monthly Spotify charges, then one anomaly at 5×
      // the price. The detector filters by amount before checking
      // cadence, so the trailing outlier gets dropped and the steady
      // run still forms a pattern. (An outlier *in the middle* would
      // create an unbridgeable cadence gap and fail — the simpler
      // algorithm requires the consistent-amount subset to also be
      // consecutive.)
      final patterns = detectRecurring(<TransactionInput>[
        TransactionInput(
          id: 's_1',
          description: 'SPOTIFY',
          amountMinor: '-999',
          currency: 'USD',
          occurredAt: DateTime.utc(2026, 1, 5),
        ),
        TransactionInput(
          id: 's_2',
          description: 'SPOTIFY',
          amountMinor: '-999',
          currency: 'USD',
          occurredAt: DateTime.utc(2026, 2, 4),
        ),
        TransactionInput(
          id: 's_3',
          description: 'SPOTIFY',
          amountMinor: '-999',
          currency: 'USD',
          occurredAt: DateTime.utc(2026, 3, 6),
        ),
        TransactionInput(
          id: 's_outlier',
          description: 'SPOTIFY',
          amountMinor: '-4999',
          currency: 'USD',
          occurredAt: DateTime.utc(2026, 4, 5),
        ),
      ]);
      expect(patterns, hasLength(1));
      expect(patterns.single.occurrenceIds, <String>['s_1', 's_2', 's_3']);
    });
  });

  group('detectRecurring — weekly cadence', () {
    test('three weekly transit charges → detected', () {
      final patterns = detectRecurring(<TransactionInput>[
        TransactionInput(
          id: 'm_1',
          description: 'METROCARD',
          amountMinor: '-3300',
          currency: 'USD',
          occurredAt: DateTime.utc(2026, 1, 5),
        ),
        TransactionInput(
          id: 'm_2',
          description: 'METROCARD',
          amountMinor: '-3300',
          currency: 'USD',
          occurredAt: DateTime.utc(2026, 1, 12),
        ),
        TransactionInput(
          id: 'm_3',
          description: 'METROCARD',
          amountMinor: '-3300',
          currency: 'USD',
          occurredAt: DateTime.utc(2026, 1, 19),
        ),
      ]);
      expect(patterns.single.cadence, RecurringCadence.weekly);
    });
  });

  group('detectRecurring — currency separation', () {
    test('same merchant in different currencies are not merged', () {
      final patterns = detectRecurring(<TransactionInput>[
        netflix(5),
        TransactionInput(
          id: 'n_cn_1',
          description: 'NETFLIX',
          amountMinor: '-7900',
          currency: 'CNY',
          occurredAt: DateTime.utc(2026, 1, 5),
        ),
        TransactionInput(
          id: 'n_cn_2',
          description: 'NETFLIX',
          amountMinor: '-7900',
          currency: 'CNY',
          occurredAt: DateTime.utc(2026, 2, 4),
        ),
      ]);
      // Each group has < 3 entries on its own, so neither qualifies.
      expect(patterns, isEmpty);
    });
  });
}
