import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/investment/domain/cost_basis/lifo_strategy.dart';

import '_helpers.dart';

void main() {
  group('LifoStrategy', () {
    const strategy = LifoStrategy();

    test('consumes the newest lot first', () {
      final lots = [
        makeLot(id: 'l-old', day: 0, costPerUnit: d('10')),
        makeLot(id: 'l-new', day: 5, costPerUnit: d('20')),
      ];
      final plan = strategy.plan(lots, d('40'));

      expect(plan.consumptions, hasLength(1));
      expect(plan.consumptions.single.lotId, 'l-new');
      expect(plan.consumptions.single.quantity, d('40'));
      expect(plan.consumptions.single.costBasis, d('800'));
    });

    test('walks across multiple lots in reverse age order', () {
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
      expect(plan.consumptions[0].lotId, 'l-3');
      expect(plan.consumptions[0].quantity, d('50'));
      expect(plan.consumptions[0].costBasis, d('1500'));
      expect(plan.consumptions[1].lotId, 'l-2');
      expect(plan.consumptions[1].quantity, d('10'));
      expect(plan.consumptions[1].costBasis, d('200'));
      expect(plan.unfulfilledQuantity, Decimal.zero);
    });

    test('LIFO produces a different cost basis than FIFO when prices rise', () {
      final lots = [
        makeLot(
          id: 'l-1',
          day: 0,
          originalQuantity: d('50'),
          costPerUnit: d('10'),
        ),
        makeLot(
          id: 'l-2',
          day: 1,
          originalQuantity: d('50'),
          costPerUnit: d('30'),
        ),
      ];
      // sell 20 shares — LIFO consumes from the newer 30/share lot.
      final plan = strategy.plan(lots, d('20'));

      expect(plan.consumptions.single.lotId, 'l-2');
      expect(plan.consumptions.single.costBasis, d('600'));
    });
  });
}
