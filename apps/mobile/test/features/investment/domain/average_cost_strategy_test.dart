import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/investment/domain/cost_basis/average_cost_strategy.dart';

import '_helpers.dart';

void main() {
  group('AverageCostStrategy', () {
    const strategy = AverageCostStrategy();

    test('uses the weighted average cost across all open lots', () {
      // 60 shares @ $10 + 40 shares @ $20 → avg = (600 + 800) / 100 = $14.
      final lots = [
        makeLot(
          id: 'l-1',
          day: 0,
          originalQuantity: d('60'),
          costPerUnit: d('10'),
        ),
        makeLot(
          id: 'l-2',
          day: 1,
          originalQuantity: d('40'),
          costPerUnit: d('20'),
        ),
      ];
      final plan = strategy.plan(lots, d('50'));

      // Sum of consumed quantity must equal requested quantity.
      final totalQty = plan.consumptions.fold<Decimal>(
        Decimal.zero,
        (s, c) => s + c.quantity,
      );
      expect(totalQty, d('50'));

      // Total cost basis must equal 50 × $14 = $700.
      final totalCost = plan.consumptions.fold<Decimal>(
        Decimal.zero,
        (s, c) => s + c.costBasis,
      );
      expect(totalCost, d('700'));

      // Distribution should be proportional: lot-1 contributes 60 % of the
      // pool so it absorbs roughly 30 of the 50 shares.
      expect(plan.consumptions, hasLength(2));
      expect(plan.consumptions[0].lotId, 'l-1');
      expect(plan.consumptions[0].quantity, d('30'));
      expect(plan.consumptions[1].lotId, 'l-2');
      expect(plan.consumptions[1].quantity, d('20'));
    });

    test('all consumptions share the same effective cost-per-unit '
        '(the weighted average)', () {
      final lots = [
        makeLot(
          id: 'l-1',
          day: 0,
          originalQuantity: d('10'),
          costPerUnit: d('5'),
        ),
        makeLot(
          id: 'l-2',
          day: 1,
          originalQuantity: d('10'),
          costPerUnit: d('15'),
        ),
      ];
      final plan = strategy.plan(lots, d('8'));

      // weighted avg = (50 + 150) / 20 = 10
      // Consumed cost basis / consumed qty should equal 10 for every entry.
      for (final c in plan.consumptions) {
        final perUnit = (c.costBasis / c.quantity).toDecimal(
          scaleOnInfinitePrecision: 16,
        );
        expect(perUnit, d('10'));
      }
    });

    test(
      'absorbs rounding remainder in the last lot to preserve total qty',
      () {
        // Three lots of equal size. Selling 10 shares means each lot should
        // contribute 10/3 — which is non-terminating in decimal, so the last
        // lot must mop up the rounding remainder.
        final lots = [
          makeLot(
            id: 'l-1',
            day: 0,
            originalQuantity: d('5'),
            costPerUnit: d('1'),
          ),
          makeLot(
            id: 'l-2',
            day: 1,
            originalQuantity: d('5'),
            costPerUnit: d('1'),
          ),
          makeLot(
            id: 'l-3',
            day: 2,
            originalQuantity: d('5'),
            costPerUnit: d('1'),
          ),
        ];
        final plan = strategy.plan(lots, d('10'));

        final totalQty = plan.consumptions.fold<Decimal>(
          Decimal.zero,
          (s, c) => s + c.quantity,
        );
        // Must add up to exactly the requested quantity, no rounding drift.
        expect(totalQty, d('10'));
      },
    );

    test(
      'reports unfulfilled quantity when total open is less than request',
      () {
        final lots = [
          makeLot(
            id: 'l-1',
            day: 0,
            originalQuantity: d('10'),
            costPerUnit: d('5'),
          ),
        ];
        final plan = strategy.plan(lots, d('25'));

        final totalQty = plan.consumptions.fold<Decimal>(
          Decimal.zero,
          (s, c) => s + c.quantity,
        );
        expect(totalQty, d('10'));
        expect(plan.unfulfilledQuantity, d('15'));
      },
    );

    test('returns empty plan when no open lots', () {
      final plan = strategy.plan(const [], d('5'));
      expect(plan.consumptions, isEmpty);
      expect(plan.unfulfilledQuantity, d('5'));
    });

    test('skips closed lots when computing the average', () {
      final lots = [
        makeLot(
          id: 'closed',
          day: 0,
          originalQuantity: d('100'),
          remainingQuantity: Decimal.zero,
          costPerUnit: d('999'),
        ),
        makeLot(
          id: 'open',
          day: 1,
          originalQuantity: d('10'),
          costPerUnit: d('5'),
        ),
      ];
      final plan = strategy.plan(lots, d('4'));

      // Closed lot must not contribute to the average — basis should be 4 * 5 = 20.
      expect(plan.consumptions, hasLength(1));
      expect(plan.consumptions.single.lotId, 'open');
      expect(plan.consumptions.single.costBasis, d('20'));
    });
  });
}
