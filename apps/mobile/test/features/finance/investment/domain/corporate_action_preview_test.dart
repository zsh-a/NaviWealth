import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/investment/domain/corporate_action_preview.dart';
import 'package:naviwealth/features/finance/investment/domain/cost_basis/fifo_strategy.dart';
import 'package:naviwealth/features/finance/investment/domain/cost_basis_engine.dart';
import 'package:naviwealth/features/finance/investment/domain/models/corporate_actions.dart';

import '_helpers.dart';

void main() {
  group('CorporateActionPreview.compute', () {
    final engine = CostBasisEngine(
      strategy: const FifoStrategy(),
      idGenerator: SequenceIds('preview').next,
    );

    test('cash dividend → updatedLots unchanged, positive cash flow, '
        'no per-lot deltas', () {
      final lots = [
        makeLot(
          id: 'l',
          accountId: 'a',
          assetId: 'X',
          remainingQuantity: d('100'),
          costPerUnit: d('10'),
        ),
      ];
      final preview = CorporateActionPreview.compute(
        engine: engine,
        action: CashDividendAction(
          id: 'cd',
          assetId: 'X',
          effectiveDate: DateTime.utc(2026, 1, 5),
          transactionId: 'tx',
          accountId: 'a',
          currency: 'USD',
          amountPerShare: d('0.5'),
          withholdingTax: Decimal.zero,
        ),
        startingLots: lots,
      );

      expect(preview.lotDeltas, isEmpty);
      expect(preview.newLots, isEmpty);
      expect(preview.updatedLots, equals(lots));
      expect(preview.cashDividend, isNotNull);
      expect(preview.cashFlow, d('50'));
      expect(preview.cashFlowCurrency, 'USD');
    });

    test('stock dividend → per-lot delta with quantity up, cost-per-unit '
        'down, total cost preserved', () {
      final lots = [
        makeLot(
          id: 'l',
          assetId: 'X',
          accountId: 'a',
          remainingQuantity: d('100'),
          originalQuantity: d('100'),
          costPerUnit: d('20'),
        ),
      ];
      final preview = CorporateActionPreview.compute(
        engine: engine,
        action: StockDividendAction(
          id: 'sd',
          assetId: 'X',
          effectiveDate: DateTime.utc(2026, 2, 1),
          bonusRatio: d('0.25'), // 1-for-4 → +25 %
        ),
        startingLots: lots,
      );

      expect(preview.lotDeltas, hasLength(1));
      final delta = preview.lotDeltas.single;
      expect(delta.quantityDelta, d('25'));
      expect(delta.costPerUnitDelta, d('-4'));
      expect(delta.costPreserved(), isTrue);
      expect(preview.newLots, isEmpty);
      expect(preview.cashFlow, Decimal.zero);
    });

    test('forward split preserves total cost and produces a delta', () {
      final lots = [
        makeLot(
          id: 'l',
          assetId: 'X',
          accountId: 'a',
          originalQuantity: d('100'),
          remainingQuantity: d('100'),
          costPerUnit: d('40'),
        ),
      ];
      final preview = CorporateActionPreview.compute(
        engine: engine,
        action: SplitAction(
          id: 's',
          assetId: 'X',
          effectiveDate: DateTime.utc(2026, 3, 1),
          ratio: d('2'),
        ),
        startingLots: lots,
      );

      final delta = preview.lotDeltas.single;
      expect(delta.before.remainingQuantity, d('100'));
      expect(delta.after.remainingQuantity, d('200'));
      expect(delta.after.costPerUnit, d('20'));
      expect(delta.costPreserved(), isTrue);
    });

    test('rights issue → newLots holds the subscribed lot, cash flow is '
        'negative (subscription cost incl. fee)', () {
      final lots = [
        makeLot(
          id: 'old',
          assetId: 'X',
          accountId: 'a',
          remainingQuantity: d('100'),
          costPerUnit: d('20'),
        ),
      ];
      final preview = CorporateActionPreview.compute(
        engine: engine,
        action: RightsIssueAction(
          id: 'ri',
          assetId: 'X',
          effectiveDate: DateTime.utc(2026, 4, 1),
          transactionId: 'tx',
          accountId: 'a',
          currency: 'CNY',
          subscribedQuantity: d('50'),
          pricePerUnit: d('15'),
          fee: d('5'),
        ),
        startingLots: lots,
      );

      expect(preview.lotDeltas, isEmpty);
      expect(preview.newLots, hasLength(1));
      expect(preview.newLots.single.remainingQuantity, d('50'));
      // -(50 * 15 + 5) = -755
      expect(preview.cashFlow, d('-755'));
      expect(preview.cashFlowCurrency, 'CNY');
    });

    test('DRIP → newLots holds the reinvested lot, no cash flow', () {
      final lots = [
        makeLot(
          id: 'old',
          assetId: 'VOO',
          accountId: 'a',
          originalQuantity: d('100'),
          remainingQuantity: d('100'),
          costPerUnit: d('400'),
        ),
      ];
      final preview = CorporateActionPreview.compute(
        engine: engine,
        action: DripAction(
          id: 'drip',
          assetId: 'VOO',
          effectiveDate: DateTime.utc(2026, 6, 15),
          transactionId: 'tx',
          accountId: 'a',
          currency: 'USD',
          amountPerShare: d('1'),
          pricePerUnit: d('500'),
          withholdingTax: Decimal.zero,
          fee: Decimal.zero,
        ),
        startingLots: lots,
      );

      expect(preview.lotDeltas, isEmpty);
      expect(preview.newLots, hasLength(1));
      expect(preview.newLots.single.originalQuantity, d('0.2'));
      expect(preview.cashFlow, Decimal.zero);
      expect(preview.cashDividend!.reinvested, isTrue);
    });
  });
}
