import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/investment/domain/cost_basis/fifo_strategy.dart';

import '_helpers.dart';

void main() {
  group('FifoStrategy', () {
    const strategy = FifoStrategy();

    test('consumes the oldest lot first', () {
      final lots = [
        makeLot(id: 'l-new', day: 5, costPerUnit: d('20')),
        makeLot(id: 'l-old', day: 0, costPerUnit: d('10')),
      ];
      final plan = strategy.plan(lots, d('40'));

      expect(plan.consumptions, hasLength(1));
      expect(plan.consumptions.single.lotId, 'l-old');
      expect(plan.consumptions.single.quantity, d('40'));
      expect(plan.consumptions.single.costBasis, d('400'));
      expect(plan.unfulfilledQuantity, Decimal.zero);
    });

    test('walks across multiple lots in age order', () {
      final lots = [
        makeLot(
          id: 'l-1',
          day: 0,
          originalQuantity: d('30'),
          costPerUnit: d('10'),
        ),
        makeLot(
          id: 'l-2',
          day: 1,
          originalQuantity: d('40'),
          costPerUnit: d('20'),
        ),
        makeLot(
          id: 'l-3',
          day: 2,
          originalQuantity: d('50'),
          costPerUnit: d('30'),
        ),
      ];
      final plan = strategy.plan(lots, d('60'));

      expect(plan.consumptions, hasLength(2));
      expect(plan.consumptions[0].lotId, 'l-1');
      expect(plan.consumptions[0].quantity, d('30'));
      expect(plan.consumptions[0].costBasis, d('300'));
      expect(plan.consumptions[1].lotId, 'l-2');
      expect(plan.consumptions[1].quantity, d('30'));
      expect(plan.consumptions[1].costBasis, d('600'));
      expect(plan.unfulfilledQuantity, Decimal.zero);
    });

    test('uses remainingQuantity, not originalQuantity', () {
      final lots = [
        makeLot(
          id: 'partial',
          day: 0,
          originalQuantity: d('100'),
          remainingQuantity: d('20'),
          costPerUnit: d('5'),
        ),
        makeLot(
          id: 'fresh',
          day: 1,
          originalQuantity: d('50'),
          costPerUnit: d('7'),
        ),
      ];
      final plan = strategy.plan(lots, d('30'));

      expect(plan.consumptions, hasLength(2));
      expect(plan.consumptions[0].lotId, 'partial');
      expect(plan.consumptions[0].quantity, d('20'));
      expect(plan.consumptions[1].lotId, 'fresh');
      expect(plan.consumptions[1].quantity, d('10'));
    });

    test('skips lots that are already closed', () {
      final lots = [
        makeLot(
          id: 'closed',
          day: 0,
          originalQuantity: d('50'),
          remainingQuantity: Decimal.zero,
          costPerUnit: d('99'),
        ),
        makeLot(id: 'open', day: 1, costPerUnit: d('10')),
      ];
      final plan = strategy.plan(lots, d('5'));

      expect(plan.consumptions, hasLength(1));
      expect(plan.consumptions.single.lotId, 'open');
    });

    test('reports unfulfilled quantity when supply is short', () {
      final lots = [
        makeLot(
          id: 'only',
          day: 0,
          originalQuantity: d('10'),
          costPerUnit: d('1'),
        ),
      ];
      final plan = strategy.plan(lots, d('25'));

      expect(plan.consumptions, hasLength(1));
      expect(plan.consumptions.single.quantity, d('10'));
      expect(plan.unfulfilledQuantity, d('15'));
    });

    test('returns an empty plan for zero-quantity sells', () {
      final lots = [makeLot(id: 'l', day: 0)];
      final plan = strategy.plan(lots, Decimal.zero);

      expect(plan.consumptions, isEmpty);
      expect(plan.unfulfilledQuantity, Decimal.zero);
    });

    test('returns an empty plan when there are no open lots', () {
      final plan = strategy.plan(const [], d('5'));

      expect(plan.consumptions, isEmpty);
      expect(plan.unfulfilledQuantity, d('5'));
    });

    test('total consumed cost basis equals sum of per-lot consumed cost', () {
      final lots = [
        makeLot(
          id: 'a',
          day: 0,
          originalQuantity: d('10'),
          costPerUnit: d('100'),
        ),
        makeLot(
          id: 'b',
          day: 1,
          originalQuantity: d('10'),
          costPerUnit: d('200'),
        ),
      ];
      final plan = strategy.plan(lots, d('15'));

      final totalCostBasis = plan.consumptions.fold<Decimal>(
        Decimal.zero,
        (s, c) => s + c.costBasis,
      );
      // 10 * 100 (lot a) + 5 * 200 (lot b) = 1000 + 1000 = 2000
      expect(totalCostBasis, d('2000'));
    });
  });
}
