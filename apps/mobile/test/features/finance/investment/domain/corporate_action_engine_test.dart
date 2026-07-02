import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/investment/domain/cost_basis/fifo_strategy.dart';
import 'package:naviwealth/features/finance/investment/domain/cost_basis_engine.dart';
import 'package:naviwealth/features/finance/investment/domain/models/corporate_actions.dart';

import '_helpers.dart';

void main() {
  group('CostBasisEngine.applyCashDividend', () {
    test('aggregates eligible shares and computes gross / net cash', () {
      final ids = SequenceIds('div');
      final engine = CostBasisEngine(
        strategy: const FifoStrategy(),
        idGenerator: ids.next,
      );
      final lots = [
        makeLot(
          id: 'l-old',
          accountId: 'a',
          assetId: 'AAPL',
          day: 0,
          originalQuantity: d('100'),
          remainingQuantity: d('80'),
          costPerUnit: d('150'),
        ),
        makeLot(
          id: 'l-new',
          accountId: 'a',
          assetId: 'AAPL',
          day: 5,
          originalQuantity: d('60'),
          remainingQuantity: d('60'),
          costPerUnit: d('170'),
        ),
      ];
      final dividend = engine.applyCashDividend(
        CashDividendAction(
          id: 'cd-1',
          assetId: 'AAPL',
          effectiveDate: DateTime.utc(2026, 6, 1),
          transactionId: 'tx-div',
          accountId: 'a',
          currency: 'USD',
          amountPerShare: d('0.25'),
          withholdingTax: d('5.25'),
        ),
        lots,
      );

      expect(dividend, isNotNull);
      expect(dividend!.id, 'div-1');
      expect(dividend.shareCount, d('140')); // 80 + 60
      // 140 * 0.25 = 35
      expect(dividend.grossAmount, d('35'));
      expect(dividend.withholdingTax, d('5.25'));
      expect(dividend.netAmount, d('29.75'));
      expect(dividend.reinvested, isFalse);
      expect(dividend.transactionId, 'tx-div');
      expect(dividend.effectiveDate, DateTime.utc(2026, 6, 1));
    });

    test('excludes lots from other accounts, other assets, and lots opened '
        'after the effective date', () {
      final engine = CostBasisEngine(strategy: const FifoStrategy());
      final lots = [
        makeLot(
          id: 'right',
          accountId: 'a',
          assetId: 'X',
          day: 0,
          originalQuantity: d('50'),
          remainingQuantity: d('50'),
        ),
        makeLot(
          id: 'wrong-acct',
          accountId: 'b',
          assetId: 'X',
          day: 0,
          originalQuantity: d('100'),
          remainingQuantity: d('100'),
        ),
        makeLot(
          id: 'wrong-asset',
          accountId: 'a',
          assetId: 'Y',
          day: 0,
          originalQuantity: d('100'),
          remainingQuantity: d('100'),
        ),
        makeLot(
          // Opened 60 days after the effective date — not held on record.
          id: 'too-young',
          accountId: 'a',
          assetId: 'X',
          day: 60,
          originalQuantity: d('200'),
          remainingQuantity: d('200'),
        ),
      ];
      final dividend = engine.applyCashDividend(
        CashDividendAction(
          id: 'cd',
          assetId: 'X',
          effectiveDate: DateTime.utc(2026, 1, 30),
          transactionId: 't',
          accountId: 'a',
          currency: 'USD',
          amountPerShare: d('1'),
          withholdingTax: Decimal.zero,
        ),
        lots,
      );

      expect(dividend!.shareCount, d('50'));
      expect(dividend.grossAmount, d('50'));
      expect(dividend.netAmount, d('50'));
    });

    test('returns null when the holder owns zero eligible shares', () {
      final engine = CostBasisEngine(strategy: const FifoStrategy());
      final dividend = engine.applyCashDividend(
        CashDividendAction(
          id: 'cd',
          assetId: 'X',
          effectiveDate: DateTime.utc(2026, 1, 1),
          transactionId: 't',
          accountId: 'a',
          currency: 'USD',
          amountPerShare: d('0.50'),
          withholdingTax: Decimal.zero,
        ),
        const [],
      );
      expect(dividend, isNull);
    });

    test('does not modify the input lots', () {
      final engine = CostBasisEngine(strategy: const FifoStrategy());
      final lots = [
        makeLot(
          id: 'l',
          accountId: 'a',
          assetId: 'X',
          remainingQuantity: d('100'),
          costPerUnit: d('10'),
        ),
      ];
      final beforeQty = lots.single.remainingQuantity;
      final beforeCost = lots.single.costPerUnit;
      engine.applyCashDividend(
        CashDividendAction(
          id: 'cd',
          assetId: 'X',
          effectiveDate: DateTime.utc(2026, 1, 1),
          transactionId: 't',
          accountId: 'a',
          currency: 'USD',
          amountPerShare: d('0.5'),
          withholdingTax: Decimal.zero,
        ),
        lots,
      );
      expect(lots.single.remainingQuantity, beforeQty);
      expect(lots.single.costPerUnit, beforeCost);
    });

    test('rejects negative per-share amount', () {
      final engine = CostBasisEngine(strategy: const FifoStrategy());
      expect(
        () => engine.applyCashDividend(
          CashDividendAction(
            id: 'cd',
            assetId: 'X',
            effectiveDate: DateTime.utc(2026, 1, 1),
            transactionId: 't',
            accountId: 'a',
            currency: 'USD',
            amountPerShare: d('-0.01'),
            withholdingTax: Decimal.zero,
          ),
          const [],
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects withholding tax greater than gross', () {
      final engine = CostBasisEngine(strategy: const FifoStrategy());
      final lots = [
        makeLot(
          id: 'l',
          accountId: 'a',
          assetId: 'X',
          remainingQuantity: d('100'),
        ),
      ];
      expect(
        () => engine.applyCashDividend(
          CashDividendAction(
            id: 'cd',
            assetId: 'X',
            effectiveDate: DateTime.utc(2026, 1, 1),
            transactionId: 't',
            accountId: 'a',
            currency: 'USD',
            amountPerShare: d('1'), // gross = 100
            withholdingTax: d('150'),
          ),
          lots,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('CostBasisEngine.applyDrip', () {
    test('reinvests net dividend into a new lot at the price per unit', () {
      final ids = SequenceIds('id');
      final engine = CostBasisEngine(
        strategy: const FifoStrategy(),
        idGenerator: ids.next,
      );
      final lots = [
        makeLot(
          id: 'l-old',
          accountId: 'a',
          assetId: 'VOO',
          day: 0,
          originalQuantity: d('200'),
          remainingQuantity: d('200'),
          costPerUnit: d('400'),
        ),
      ];
      final result = engine.applyDrip(
        DripAction(
          id: 'drip-1',
          assetId: 'VOO',
          effectiveDate: DateTime.utc(2026, 6, 15),
          transactionId: 'tx-drip',
          accountId: 'a',
          currency: 'USD',
          amountPerShare: d('1'), // gross = 200
          pricePerUnit: d('500'), // → buys 0.4 shares
          withholdingTax: Decimal.zero,
          fee: Decimal.zero,
        ),
        lots,
      );

      expect(result.cashDividend.shareCount, d('200'));
      expect(result.cashDividend.grossAmount, d('200'));
      expect(result.cashDividend.netAmount, d('200'));
      expect(result.cashDividend.reinvested, isTrue);

      final newLot = result.newLot;
      expect(newLot.id, 'id-1'); // first id consumed by the new lot
      expect(newLot.openingTransactionId, 'tx-drip');
      expect(newLot.assetId, 'VOO');
      expect(newLot.accountId, 'a');
      expect(newLot.originalQuantity, d('0.4'));
      expect(newLot.remainingQuantity, d('0.4'));
      expect(newLot.costPerUnit, d('500'));
      // Total cost equals net dividend (no fee).
      expect(newLot.remainingCost, d('200'));
      expect(newLot.openedAt, DateTime.utc(2026, 6, 15));

      // updatedLots = [...input, newLot]
      expect(result.updatedLots, hasLength(lots.length + 1));
      expect(result.updatedLots.last, newLot);
    });

    test('subtracts withholding tax before reinvestment', () {
      final engine = CostBasisEngine(strategy: const FifoStrategy());
      final lots = [
        makeLot(
          id: 'l',
          accountId: 'a',
          assetId: 'X',
          originalQuantity: d('100'),
          remainingQuantity: d('100'),
        ),
      ];
      final result = engine.applyDrip(
        DripAction(
          id: 'drip',
          assetId: 'X',
          effectiveDate: DateTime.utc(2026, 1, 1),
          transactionId: 't',
          accountId: 'a',
          currency: 'USD',
          amountPerShare: d('2'), // gross = 200
          pricePerUnit: d('100'),
          withholdingTax: d('30'),
          fee: Decimal.zero,
        ),
        lots,
      );
      // net 170, reinvested at 100 → 1.7 shares.
      expect(result.cashDividend.netAmount, d('170'));
      expect(result.newLot.remainingQuantity, d('1.7'));
      expect(result.newLot.remainingCost, d('170'));
    });

    test('bakes the reinvestment fee into the new lot cost basis', () {
      final engine = CostBasisEngine(strategy: const FifoStrategy());
      final lots = [
        makeLot(
          id: 'l',
          accountId: 'a',
          assetId: 'X',
          originalQuantity: d('100'),
          remainingQuantity: d('100'),
        ),
      ];
      final result = engine.applyDrip(
        DripAction(
          id: 'drip',
          assetId: 'X',
          effectiveDate: DateTime.utc(2026, 1, 1),
          transactionId: 't',
          accountId: 'a',
          currency: 'USD',
          amountPerShare: d('5'), // gross = 500
          pricePerUnit: d('100'),
          withholdingTax: Decimal.zero,
          fee: d('5'),
        ),
        lots,
      );
      // (500 - 5) / 100 = 4.95 shares; cost basis = 4.95 * 100 + 5 = 500.
      expect(result.newLot.remainingQuantity, d('4.95'));
      expect(result.newLot.costPerUnit, d('101.0101010101010101'));
      expect(
        result.newLot.remainingCost,
        d('499.999999999999999995'), // rounding at scale 16
      );
    });

    test('rejects DRIP when no shares are held', () {
      final engine = CostBasisEngine(strategy: const FifoStrategy());
      expect(
        () => engine.applyDrip(
          DripAction(
            id: 'drip',
            assetId: 'X',
            effectiveDate: DateTime.utc(2026, 1, 1),
            transactionId: 't',
            accountId: 'a',
            currency: 'USD',
            amountPerShare: d('1'),
            pricePerUnit: d('10'),
            withholdingTax: Decimal.zero,
            fee: Decimal.zero,
          ),
          const [],
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects DRIP when fee exceeds net dividend', () {
      final engine = CostBasisEngine(strategy: const FifoStrategy());
      final lots = [
        makeLot(
          id: 'l',
          accountId: 'a',
          assetId: 'X',
          originalQuantity: d('10'),
          remainingQuantity: d('10'),
        ),
      ];
      expect(
        () => engine.applyDrip(
          DripAction(
            id: 'drip',
            assetId: 'X',
            effectiveDate: DateTime.utc(2026, 1, 1),
            transactionId: 't',
            accountId: 'a',
            currency: 'USD',
            amountPerShare: d('1'), // gross = 10
            pricePerUnit: d('10'),
            withholdingTax: Decimal.zero,
            fee: d('20'), // exceeds net
          ),
          lots,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects DRIP with non-positive amount or price', () {
      final engine = CostBasisEngine(strategy: const FifoStrategy());
      final lots = [
        makeLot(
          id: 'l',
          accountId: 'a',
          assetId: 'X',
          remainingQuantity: d('1'),
        ),
      ];
      DripAction make({required Decimal amount, required Decimal price}) =>
          DripAction(
            id: 'drip',
            assetId: 'X',
            effectiveDate: DateTime.utc(2026, 1, 1),
            transactionId: 't',
            accountId: 'a',
            currency: 'USD',
            amountPerShare: amount,
            pricePerUnit: price,
            withholdingTax: Decimal.zero,
            fee: Decimal.zero,
          );
      expect(
        () => engine.applyDrip(make(amount: Decimal.zero, price: d('1')), lots),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => engine.applyDrip(make(amount: d('1'), price: Decimal.zero), lots),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
