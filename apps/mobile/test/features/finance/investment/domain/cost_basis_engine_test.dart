import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/investment/domain/cost_basis/average_cost_strategy.dart';
import 'package:naviwealth/features/finance/investment/domain/cost_basis/cost_basis_method.dart';
import 'package:naviwealth/features/finance/investment/domain/cost_basis/fifo_strategy.dart';
import 'package:naviwealth/features/finance/investment/domain/cost_basis/lifo_strategy.dart';
import 'package:naviwealth/features/finance/investment/domain/cost_basis_engine.dart';
import 'package:naviwealth/features/finance/investment/domain/models/corporate_actions.dart';
import 'package:naviwealth/features/finance/investment/domain/models/trade_events.dart';

import '_helpers.dart';

void main() {
  group('CostBasisEngine.applyBuy', () {
    test('opens a fresh lot at price + prorated fees', () {
      final ids = SequenceIds('lot');
      final engine = CostBasisEngine(
        strategy: const FifoStrategy(),
        idGenerator: ids.next,
      );
      final lot = engine.applyBuy(
        BuyEvent(
          transactionId: 'tx-buy-1',
          accountId: 'acct-1',
          assetId: 'AAPL',
          currency: 'USD',
          quantity: d('100'),
          pricePerUnit: d('150'),
          fee: d('10'),
          tradeDate: DateTime.utc(2026, 1, 5),
        ),
      );

      expect(lot.id, 'lot-1');
      expect(lot.openingTransactionId, 'tx-buy-1');
      expect(lot.originalQuantity, d('100'));
      expect(lot.remainingQuantity, d('100'));
      // (100 * 150 + 10) / 100 = 150.10
      expect(lot.costPerUnit, d('150.1'));
      expect(lot.openedAt, DateTime.utc(2026, 1, 5));
    });

    test('rejects non-positive quantity', () {
      final engine = CostBasisEngine(strategy: const FifoStrategy());
      expect(
        () => engine.applyBuy(
          BuyEvent(
            transactionId: 'tx',
            accountId: 'a',
            assetId: 'X',
            currency: 'USD',
            quantity: Decimal.zero,
            pricePerUnit: d('1'),
            fee: Decimal.zero,
            tradeDate: DateTime.utc(2026, 1, 1),
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('CostBasisEngine.applySell — FIFO', () {
    test('consumes oldest lot first, emits realized PnL with buy- and '
        'sell-side fees attributed', () {
      final ids = SequenceIds('rid');
      final engine = CostBasisEngine(
        strategy: const FifoStrategy(),
        idGenerator: ids.next,
      );
      final lots = [
        makeLot(
          id: 'l-old',
          day: 0,
          assetId: 'AAPL',
          accountId: 'a',
          originalQuantity: d('40'),
          costPerUnit: d('10'),
        ),
        makeLot(
          id: 'l-new',
          day: 5,
          assetId: 'AAPL',
          accountId: 'a',
          originalQuantity: d('60'),
          costPerUnit: d('15'),
        ),
      ];
      final result = engine.applySell(
        SellEvent(
          transactionId: 'tx-sell',
          accountId: 'a',
          assetId: 'AAPL',
          currency: 'USD',
          quantity: d('50'),
          pricePerUnit: d('20'),
          fee: d('5'),
          tradeDate: DateTime.utc(2026, 2, 1),
        ),
        lots,
      );

      expect(result.unfulfilledQuantity, Decimal.zero);
      expect(result.realizedPnL, hasLength(2));

      // Lot l-old is fully consumed (40), lot l-new partially (10).
      final r1 = result.realizedPnL[0];
      expect(r1.lotId, 'l-old');
      expect(r1.quantity, d('40'));
      expect(r1.costBasis, d('400'));
      expect(r1.proceeds, d('800'));
      // Fees prorated: 40 / 50 of the $5 sell fee = $4
      expect(r1.fees, d('4'));
      // gain = proceeds - fees - costBasis = 800 - 4 - 400 = 396
      expect(r1.gain, d('396'));

      final r2 = result.realizedPnL[1];
      expect(r2.lotId, 'l-new');
      expect(r2.quantity, d('10'));
      expect(r2.costBasis, d('150'));
      expect(r2.proceeds, d('200'));
      expect(r2.fees, d('1'));
      expect(r2.gain, d('49'));

      // Updated lots: l-old fully closed, l-new reduced.
      final updatedOld = result.updatedLots.firstWhere((l) => l.id == 'l-old');
      final updatedNew = result.updatedLots.firstWhere((l) => l.id == 'l-new');
      expect(updatedOld.remainingQuantity, Decimal.zero);
      expect(updatedOld.isClosed, isTrue);
      expect(updatedNew.remainingQuantity, d('50'));
    });

    test('does not touch lots from other accounts or other assets', () {
      final engine = CostBasisEngine(strategy: const FifoStrategy());
      final lots = [
        makeLot(id: 'sameAsset-otherAcct', accountId: 'b', assetId: 'AAPL'),
        makeLot(id: 'otherAsset-sameAcct', accountId: 'a', assetId: 'GOOG'),
        makeLot(id: 'match', accountId: 'a', assetId: 'AAPL'),
      ];
      final result = engine.applySell(
        SellEvent(
          transactionId: 't',
          accountId: 'a',
          assetId: 'AAPL',
          currency: 'USD',
          quantity: d('10'),
          pricePerUnit: d('20'),
          fee: Decimal.zero,
          tradeDate: DateTime.utc(2026, 2, 1),
        ),
        lots,
      );

      expect(result.realizedPnL, hasLength(1));
      expect(result.realizedPnL.single.lotId, 'match');

      // Untouched lots preserve their full quantities.
      final other1 = result.updatedLots.firstWhere(
        (l) => l.id == 'sameAsset-otherAcct',
      );
      final other2 = result.updatedLots.firstWhere(
        (l) => l.id == 'otherAsset-sameAcct',
      );
      expect(other1.remainingQuantity, d('100'));
      expect(other2.remainingQuantity, d('100'));
    });

    test('reports unfulfilled quantity instead of throwing', () {
      final engine = CostBasisEngine(strategy: const FifoStrategy());
      final lots = [
        makeLot(
          id: 'l',
          day: 0,
          originalQuantity: d('10'),
          costPerUnit: d('5'),
        ),
      ];
      final result = engine.applySell(
        SellEvent(
          transactionId: 't',
          accountId: 'acct-1',
          assetId: 'asset-1',
          currency: 'USD',
          quantity: d('25'),
          pricePerUnit: d('10'),
          fee: Decimal.zero,
          tradeDate: DateTime.utc(2026, 2, 1),
        ),
        lots,
      );

      expect(result.unfulfilledQuantity, d('15'));
      expect(result.realizedPnL.single.quantity, d('10'));
    });
  });

  group('CostBasisEngine.applySell — LIFO vs FIFO comparison', () {
    test('LIFO and FIFO yield different cost bases when prices change', () {
      final lots = [
        makeLot(
          id: 'old',
          day: 0,
          originalQuantity: d('50'),
          costPerUnit: d('10'),
        ),
        makeLot(
          id: 'new',
          day: 1,
          originalQuantity: d('50'),
          costPerUnit: d('30'),
        ),
      ];
      final fifoEngine = CostBasisEngine.forMethod(CostBasisMethod.fifo);
      final lifoEngine = CostBasisEngine.forMethod(CostBasisMethod.lifo);

      final sell = SellEvent(
        transactionId: 't',
        accountId: 'acct-1',
        assetId: 'asset-1',
        currency: 'USD',
        quantity: d('20'),
        pricePerUnit: d('40'),
        fee: Decimal.zero,
        tradeDate: DateTime.utc(2026, 2, 1),
      );

      final fifoBasis = fifoEngine
          .applySell(sell, lots)
          .realizedPnL
          .fold<Decimal>(Decimal.zero, (s, r) => s + r.costBasis);
      final lifoBasis = lifoEngine
          .applySell(sell, lots)
          .realizedPnL
          .fold<Decimal>(Decimal.zero, (s, r) => s + r.costBasis);

      expect(fifoBasis, d('200')); // 20 * 10
      expect(lifoBasis, d('600')); // 20 * 30
    });
  });

  group('CostBasisEngine.applySell — Average', () {
    test('average-cost engine matches the strategy output', () {
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
      final engine = CostBasisEngine(strategy: const AverageCostStrategy());
      final result = engine.applySell(
        SellEvent(
          transactionId: 't',
          accountId: 'acct-1',
          assetId: 'asset-1',
          currency: 'USD',
          quantity: d('50'),
          pricePerUnit: d('25'),
          fee: Decimal.zero,
          tradeDate: DateTime.utc(2026, 2, 1),
        ),
        lots,
      );

      final totalCost = result.realizedPnL.fold<Decimal>(
        Decimal.zero,
        (s, r) => s + r.costBasis,
      );
      // Weighted avg = $14 → 50 * 14 = $700.
      expect(totalCost, d('700'));

      // Total proceeds = 50 * $25 = $1,250 → realized gain $550.
      final totalGain = result.realizedPnL.fold<Decimal>(
        Decimal.zero,
        (s, r) => s + r.gain,
      );
      expect(totalGain, d('550'));
    });
  });

  group('CostBasisEngine.applySplit', () {
    test('forward 2-for-1 split doubles quantity and halves cost per unit', () {
      final engine = CostBasisEngine(strategy: const FifoStrategy());
      final lots = [
        makeLot(
          id: 'l-1',
          assetId: 'AAPL',
          originalQuantity: d('100'),
          remainingQuantity: d('100'),
          costPerUnit: d('20'),
        ),
        makeLot(id: 'l-other', assetId: 'GOOG', costPerUnit: d('99')),
      ];
      final updated = engine.applySplit(
        SplitAction(
          id: 's',
          assetId: 'AAPL',
          ratio: d('2'),
          effectiveDate: DateTime.utc(2026, 3, 1),
        ),
        lots,
      );

      final aapl = updated.firstWhere((l) => l.id == 'l-1');
      expect(aapl.originalQuantity, d('200'));
      expect(aapl.remainingQuantity, d('200'));
      expect(aapl.costPerUnit, d('10'));
      // Total cost preserved.
      expect(aapl.remainingCost, d('2000'));

      // Other-asset lot untouched.
      final goog = updated.firstWhere((l) => l.id == 'l-other');
      expect(goog.costPerUnit, d('99'));
    });

    test('reverse 1-for-10 split divides quantity and multiplies cost', () {
      final engine = CostBasisEngine(strategy: const FifoStrategy());
      final lots = [
        makeLot(
          id: 'l',
          assetId: 'X',
          originalQuantity: d('1000'),
          remainingQuantity: d('800'),
          costPerUnit: d('5'),
        ),
      ];
      final updated = engine.applySplit(
        SplitAction(
          id: 's',
          assetId: 'X',
          ratio: d('0.1'),
          effectiveDate: DateTime.utc(2026, 3, 1),
        ),
        lots,
      );

      final lot = updated.single;
      expect(lot.originalQuantity, d('100'));
      expect(lot.remainingQuantity, d('80'));
      expect(lot.costPerUnit, d('50'));
      // Remaining cost preserved.
      expect(lot.remainingCost, d('4000'));
    });

    test('total cost is preserved across forward and reverse splits '
        'when intermediate prices are exact', () {
      // Compound splits only preserve total cost exactly when each
      // intermediate cost-per-unit is representable at the configured scale.
      // Here 25/5 = 5 (exact) and 5/0.5 = 10 (exact), so the round-trip is
      // lossless. Non-terminating ratios (e.g. 3-for-1 from $25 → $8.333…)
      // accumulate rounding at the configured scale by design.
      final engine = CostBasisEngine(strategy: const FifoStrategy());
      final lots = [
        makeLot(
          id: 'l',
          assetId: 'X',
          originalQuantity: d('100'),
          remainingQuantity: d('100'),
          costPerUnit: d('25'),
        ),
      ];
      final originalCost = lots.first.remainingCost;

      var step = engine.applySplit(
        SplitAction(
          id: 's1',
          assetId: 'X',
          ratio: d('5'),
          effectiveDate: DateTime.utc(2026, 3, 1),
        ),
        lots,
      );
      step = engine.applySplit(
        SplitAction(
          id: 's2',
          assetId: 'X',
          ratio: d('0.5'),
          effectiveDate: DateTime.utc(2026, 4, 1),
        ),
        step,
      );

      expect(step.single.remainingCost, originalCost);
    });

    test('rejects a non-positive ratio', () {
      final engine = CostBasisEngine(strategy: const FifoStrategy());
      expect(
        () => engine.applySplit(
          SplitAction(
            id: 's',
            assetId: 'X',
            ratio: Decimal.zero,
            effectiveDate: DateTime.utc(2026, 3, 1),
          ),
          const [],
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('CostBasisEngine.applyStockDividend', () {
    test('1-for-10 bonus increases quantity by 10 % and reduces cost', () {
      final engine = CostBasisEngine(strategy: const FifoStrategy());
      final lots = [
        makeLot(
          id: 'l',
          assetId: 'X',
          originalQuantity: d('100'),
          remainingQuantity: d('100'),
          costPerUnit: d('11'),
        ),
      ];
      final updated = engine.applyStockDividend(
        StockDividendAction(
          id: 'sd',
          assetId: 'X',
          bonusRatio: d('0.1'),
          effectiveDate: DateTime.utc(2026, 3, 1),
        ),
        lots,
      );

      final lot = updated.single;
      expect(lot.originalQuantity, d('110'));
      expect(lot.remainingQuantity, d('110'));
      // Cost preserved: 110 * 10 = 1100 = 100 * 11.
      expect(lot.costPerUnit, d('10'));
      expect(lot.remainingCost, d('1100'));
    });

    test('zero bonus is a no-op', () {
      final engine = CostBasisEngine(strategy: const FifoStrategy());
      final lots = [makeLot(id: 'l', assetId: 'X', costPerUnit: d('7'))];
      final updated = engine.applyStockDividend(
        StockDividendAction(
          id: 'sd',
          assetId: 'X',
          bonusRatio: Decimal.zero,
          effectiveDate: DateTime.utc(2026, 3, 1),
        ),
        lots,
      );

      expect(updated.single.remainingQuantity, lots.single.remainingQuantity);
      expect(updated.single.costPerUnit, lots.single.costPerUnit);
    });

    test('rejects a negative bonus ratio', () {
      final engine = CostBasisEngine(strategy: const FifoStrategy());
      expect(
        () => engine.applyStockDividend(
          StockDividendAction(
            id: 'sd',
            assetId: 'X',
            bonusRatio: d('-0.1'),
            effectiveDate: DateTime.utc(2026, 3, 1),
          ),
          const [],
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('CostBasisEngine.applyRightsIssue', () {
    test('creates a fresh lot at the subscription price', () {
      final ids = SequenceIds('lot');
      final engine = CostBasisEngine(
        strategy: const FifoStrategy(),
        idGenerator: ids.next,
      );
      final lot = engine.applyRightsIssue(
        RightsIssueAction(
          id: 'ri',
          assetId: 'X',
          effectiveDate: DateTime.utc(2026, 3, 1),
          transactionId: 'tx-rights',
          accountId: 'acct-1',
          currency: 'CNY',
          subscribedQuantity: d('200'),
          pricePerUnit: d('5'),
          fee: d('20'),
        ),
      );

      expect(lot.id, 'lot-1');
      expect(lot.openingTransactionId, 'tx-rights');
      expect(lot.assetId, 'X');
      expect(lot.originalQuantity, d('200'));
      // (200 * 5 + 20) / 200 = 5.10
      expect(lot.costPerUnit, d('5.1'));
      expect(lot.openedAt, DateTime.utc(2026, 3, 1));
    });
  });

  group('CostBasisEngine.forMethod factory', () {
    test('builds the right strategy for each enum value', () {
      expect(
        CostBasisEngine.forMethod(CostBasisMethod.fifo).strategy,
        isA<FifoStrategy>(),
      );
      expect(
        CostBasisEngine.forMethod(CostBasisMethod.lifo).strategy,
        isA<LifoStrategy>(),
      );
      expect(
        CostBasisEngine.forMethod(CostBasisMethod.average).strategy,
        isA<AverageCostStrategy>(),
      );
    });
  });
}
