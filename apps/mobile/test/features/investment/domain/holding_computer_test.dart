import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/data/domain/enums.dart' hide CostBasisMethod;
import 'package:naviwealth/data/domain/hlc.dart';
import 'package:naviwealth/data/domain/sync_meta.dart';
import 'package:naviwealth/data/domain/transaction.dart';
import 'package:naviwealth/domain/entities/fx_rate.dart';
import 'package:naviwealth/domain/services/currency_converter.dart';
import 'package:naviwealth/features/investment/domain/cost_basis/cost_basis_method.dart';
import 'package:naviwealth/features/investment/domain/cost_basis_engine.dart';
import 'package:naviwealth/features/investment/domain/holding_computer.dart';
import 'package:naviwealth/features/investment/domain/holding_price_source.dart';
import 'package:naviwealth/features/investment/domain/models/corporate_actions.dart';

import '_helpers.dart';

Transaction _tx({
  required String id,
  required TransactionType type,
  required String accountId,
  required String? assetId,
  required Decimal quantity,
  required Decimal price,
  required String currency,
  required DateTime tradeDate,
  Decimal? fee,
  String owner = 'user-1',
}) {
  return Transaction(
    id: id,
    accountId: accountId,
    assetId: assetId,
    type: type,
    quantity: quantity,
    price: price,
    currency: currency,
    tradeDate: tradeDate,
    fee: fee,
    sync: SyncMeta(
      ownerUserId: owner,
      updatedAt: tradeDate,
      updatedByDevice: 'dev-1',
      hlc: Hlc.zero('node-1'),
    ),
  );
}

CurrencyConverter _identityConverter() =>
    FxRateCurrencyConverter(InMemoryFxRateLookup(const []));

void main() {
  group('HoldingComputer.replay — increase / decrease', () {
    test('a buy creates a lot, a sell consumes it (FIFO)', () {
      final computer = HoldingComputer(
        engine: CostBasisEngine.forMethod(
          CostBasisMethod.fifo,
          idGenerator: SequenceIds('lot').next,
        ),
      );
      final txns = [
        _tx(
          id: 'tx-buy',
          type: TransactionType.buy,
          accountId: 'a',
          assetId: 'AAPL',
          quantity: d('100'),
          price: d('150'),
          currency: 'USD',
          tradeDate: DateTime.utc(2026, 1, 5),
          fee: d('10'),
        ),
        _tx(
          id: 'tx-sell',
          type: TransactionType.sell,
          accountId: 'a',
          assetId: 'AAPL',
          quantity: d('40'),
          price: d('200'),
          currency: 'USD',
          tradeDate: DateTime.utc(2026, 2, 1),
          fee: d('5'),
        ),
      ];

      final result = computer.replay(initialLots: const [], transactions: txns);

      // 60 shares remain, with the buy-side fee baked into cost-per-unit
      // (150 * 100 + 10) / 100 = 150.10. Realized P&L lives on RealizedPnL.
      expect(result.lots, hasLength(1));
      expect(result.lots.single.remainingQuantity, d('60'));
      expect(result.lots.single.costPerUnit, d('150.1'));
      expect(result.realizedPnL, hasLength(1));
      expect(result.realizedPnL.single.quantity, d('40'));
      expect(result.unfulfilledSells, isEmpty);
    });

    test('reinvest is treated as a buy', () {
      final computer = HoldingComputer(
        engine: CostBasisEngine.forMethod(
          CostBasisMethod.fifo,
          idGenerator: SequenceIds('lot').next,
        ),
      );
      final txns = [
        _tx(
          id: 'tx-reinvest',
          type: TransactionType.reinvest,
          accountId: 'a',
          assetId: 'VTI',
          quantity: d('5'),
          price: d('200'),
          currency: 'USD',
          tradeDate: DateTime.utc(2026, 3, 1),
        ),
      ];
      final result = computer.replay(initialLots: const [], transactions: txns);

      expect(result.lots, hasLength(1));
      expect(result.lots.single.remainingQuantity, d('5'));
      expect(result.lots.single.costPerUnit, d('200'));
    });

    test('non-position transactions (deposit, fee, dividend) are no-ops', () {
      final computer = HoldingComputer(
        engine: CostBasisEngine.forMethod(CostBasisMethod.fifo),
      );
      final txns = [
        _tx(
          id: 'cash-1',
          type: TransactionType.deposit,
          accountId: 'a',
          assetId: null,
          quantity: d('1000'),
          price: Decimal.one,
          currency: 'USD',
          tradeDate: DateTime.utc(2026, 1, 1),
        ),
        _tx(
          id: 'fee-1',
          type: TransactionType.fee,
          accountId: 'a',
          assetId: null,
          quantity: d('5'),
          price: Decimal.one,
          currency: 'USD',
          tradeDate: DateTime.utc(2026, 1, 2),
        ),
        _tx(
          id: 'div-1',
          type: TransactionType.dividend,
          accountId: 'a',
          assetId: 'AAPL',
          quantity: Decimal.zero,
          price: d('1.50'),
          currency: 'USD',
          tradeDate: DateTime.utc(2026, 1, 3),
        ),
      ];
      final result = computer.replay(initialLots: const [], transactions: txns);

      expect(result.lots, isEmpty);
      expect(result.realizedPnL, isEmpty);
    });

    test('out-of-order transactions are sorted by trade date', () {
      final computer = HoldingComputer(
        engine: CostBasisEngine.forMethod(
          CostBasisMethod.fifo,
          idGenerator: SequenceIds('lot').next,
        ),
      );
      final later = _tx(
        id: 'tx-2',
        type: TransactionType.buy,
        accountId: 'a',
        assetId: 'AAPL',
        quantity: d('50'),
        price: d('200'),
        currency: 'USD',
        tradeDate: DateTime.utc(2026, 2, 1),
      );
      final earlier = _tx(
        id: 'tx-1',
        type: TransactionType.buy,
        accountId: 'a',
        assetId: 'AAPL',
        quantity: d('100'),
        price: d('150'),
        currency: 'USD',
        tradeDate: DateTime.utc(2026, 1, 1),
      );
      // Pass them out of order.
      final result = computer.replay(
        initialLots: const [],
        transactions: [later, earlier],
      );

      // Lots are inserted in chronological order, so lot-1 is the older one.
      expect(result.lots, hasLength(2));
      expect(result.lots[0].costPerUnit, d('150'));
      expect(result.lots[1].costPerUnit, d('200'));
    });

    test('oversold sell records unfulfilled quantity instead of throwing', () {
      final computer = HoldingComputer(
        engine: CostBasisEngine.forMethod(
          CostBasisMethod.fifo,
          idGenerator: SequenceIds('lot').next,
        ),
      );
      final txns = [
        _tx(
          id: 'tx-buy',
          type: TransactionType.buy,
          accountId: 'a',
          assetId: 'AAPL',
          quantity: d('10'),
          price: d('100'),
          currency: 'USD',
          tradeDate: DateTime.utc(2026, 1, 1),
        ),
        _tx(
          id: 'tx-oversold',
          type: TransactionType.sell,
          accountId: 'a',
          assetId: 'AAPL',
          quantity: d('25'),
          price: d('120'),
          currency: 'USD',
          tradeDate: DateTime.utc(2026, 2, 1),
        ),
      ];
      final result = computer.replay(initialLots: const [], transactions: txns);

      expect(result.unfulfilledSells, hasLength(1));
      expect(result.unfulfilledSells.single.transactionId, 'tx-oversold');
      expect(result.unfulfilledSells.single.unfulfilledQuantity, d('15'));
    });
  });

  group('HoldingComputer.replay — corporate actions', () {
    test('a 2-for-1 split between buys is applied to the open position', () {
      final computer = HoldingComputer(
        engine: CostBasisEngine.forMethod(
          CostBasisMethod.fifo,
          idGenerator: SequenceIds('lot').next,
        ),
      );
      final result = computer.replay(
        initialLots: const [],
        transactions: [
          _tx(
            id: 'tx-buy',
            type: TransactionType.buy,
            accountId: 'a',
            assetId: 'AAPL',
            quantity: d('100'),
            price: d('150'),
            currency: 'USD',
            tradeDate: DateTime.utc(2026, 1, 5),
          ),
        ],
        corporateActions: [
          SplitAction(
            id: 'split-1',
            assetId: 'AAPL',
            ratio: d('2'),
            effectiveDate: DateTime.utc(2026, 2, 10),
          ),
        ],
      );

      expect(result.lots, hasLength(1));
      expect(result.lots.single.remainingQuantity, d('200'));
      expect(result.lots.single.costPerUnit, d('75'));
    });

    test('on the same day, a corporate action runs before transactions', () {
      // 1-for-2 reverse split + same-day sell of half: must split first
      // (cost basis doubles, qty halves) then sell consumes the new lot.
      final computer = HoldingComputer(
        engine: CostBasisEngine.forMethod(
          CostBasisMethod.fifo,
          idGenerator: SequenceIds('lot').next,
        ),
      );
      final result = computer.replay(
        initialLots: [
          makeLot(
            id: 'l',
            assetId: 'X',
            originalQuantity: d('100'),
            remainingQuantity: d('100'),
            costPerUnit: d('10'),
          ),
        ],
        transactions: [
          _tx(
            id: 'sell-after-split',
            type: TransactionType.sell,
            accountId: 'acct-1',
            assetId: 'X',
            quantity: d('25'),
            price: d('30'),
            currency: 'USD',
            tradeDate: DateTime.utc(2026, 5, 1),
          ),
        ],
        corporateActions: [
          SplitAction(
            id: 'rs',
            assetId: 'X',
            ratio: d('0.5'),
            effectiveDate: DateTime.utc(2026, 5, 1),
          ),
        ],
      );

      // Post-split: 50 shares @ $20. Sell 25 leaves 25 @ $20.
      expect(result.lots.single.remainingQuantity, d('25'));
      expect(result.lots.single.costPerUnit, d('20'));
    });
  });

  group('HoldingComputer.snapshot — single currency', () {
    test('aggregates open lots and computes weight per asset', () {
      final computer = HoldingComputer(
        engine: CostBasisEngine.forMethod(CostBasisMethod.fifo),
      );
      final lots = [
        makeLot(
          id: 'l-aapl',
          assetId: 'AAPL',
          accountId: 'a',
          originalQuantity: d('10'),
          remainingQuantity: d('10'),
          costPerUnit: d('100'),
          currency: 'USD',
        ),
        makeLot(
          id: 'l-goog',
          assetId: 'GOOG',
          accountId: 'a',
          originalQuantity: d('5'),
          remainingQuantity: d('5'),
          costPerUnit: d('200'),
          currency: 'USD',
        ),
      ];
      final prices = InMemoryHoldingPriceSource(const []);
      // ignore: parameter_assignments — building observations explicitly.
      final pricesWithData = InMemoryHoldingPriceSource([
        HoldingPriceObservation(
          assetId: 'AAPL',
          price: d('150'),
          currency: 'USD',
          asOf: DateTime.utc(2026, 4, 1),
        ),
        HoldingPriceObservation(
          assetId: 'GOOG',
          price: d('300'),
          currency: 'USD',
          asOf: DateTime.utc(2026, 4, 1),
        ),
      ]);
      // Confirm the empty source returns null (sanity check).
      expect(prices.priceFor('AAPL', asOf: DateTime.utc(2026, 4, 1)), isNull);

      final result = computer.snapshot(
        lots: lots,
        asOf: DateTime.utc(2026, 4, 1),
        prices: pricesWithData,
        converter: _identityConverter(),
        baseCurrency: 'USD',
      );

      // AAPL: qty=10, mv=$1500, cost=$1000, pnl=$500
      // GOOG: qty=5,  mv=$1500, cost=$1000, pnl=$500
      // Total MV = $3000 → weight 0.5 each.
      final aapl = result['AAPL']!;
      final goog = result['GOOG']!;
      expect(aapl.quantity, d('10'));
      expect(aapl.marketValueInBase, d('1500'));
      expect(aapl.costBasisInBase, d('1000'));
      expect(aapl.unrealizedPnlInBase, d('500'));
      expect(aapl.weight, d('0.5'));
      expect(goog.weight, d('0.5'));
      expect(aapl.assetCurrency, 'USD');
      expect(aapl.baseCurrency, 'USD');
    });

    test('closed lots are filtered out of aggregation', () {
      final computer = HoldingComputer(
        engine: CostBasisEngine.forMethod(CostBasisMethod.fifo),
      );
      final lots = [
        makeLot(
          id: 'l-open',
          assetId: 'X',
          originalQuantity: d('20'),
          remainingQuantity: d('20'),
          costPerUnit: d('5'),
          currency: 'USD',
        ),
        makeLot(
          id: 'l-closed',
          assetId: 'X',
          originalQuantity: d('30'),
          remainingQuantity: Decimal.zero,
          costPerUnit: d('7'),
          currency: 'USD',
        ),
      ];
      final result = computer.snapshot(
        lots: lots,
        asOf: DateTime.utc(2026, 4, 1),
        prices: InMemoryHoldingPriceSource([
          HoldingPriceObservation(
            assetId: 'X',
            price: d('10'),
            currency: 'USD',
            asOf: DateTime.utc(2026, 4, 1),
          ),
        ]),
        converter: _identityConverter(),
        baseCurrency: 'USD',
      );

      // Only the open lot of 20 @ $5 cost: cost basis = $100, mv = $200.
      final x = result['X']!;
      expect(x.quantity, d('20'));
      expect(x.costBasisInBase, d('100'));
      expect(x.marketValueInBase, d('200'));
    });

    test('missing price → snapshot stays present with zero market value', () {
      final computer = HoldingComputer(
        engine: CostBasisEngine.forMethod(CostBasisMethod.fifo),
      );
      final lots = [
        makeLot(
          id: 'l',
          assetId: 'X',
          originalQuantity: d('10'),
          remainingQuantity: d('10'),
          costPerUnit: d('5'),
          currency: 'USD',
        ),
      ];
      final result = computer.snapshot(
        lots: lots,
        asOf: DateTime.utc(2026, 4, 1),
        prices: InMemoryHoldingPriceSource(const []),
        converter: _identityConverter(),
        baseCurrency: 'USD',
      );

      final x = result['X']!;
      expect(x.quantity, d('10'));
      expect(x.marketValueInBase, Decimal.zero);
      expect(x.costBasisInBase, d('50'));
      // Unrealized PnL = -costBasis when no price.
      expect(x.unrealizedPnlInBase, d('-50'));
      // No portfolio value → all weights collapse to zero.
      expect(x.weight, Decimal.zero);
    });

    test('rejects an asset with mixed-currency lots', () {
      final computer = HoldingComputer(
        engine: CostBasisEngine.forMethod(CostBasisMethod.fifo),
      );
      final lots = [
        makeLot(
          id: 'l-usd',
          assetId: 'X',
          remainingQuantity: d('1'),
          costPerUnit: d('1'),
          currency: 'USD',
        ),
        makeLot(
          id: 'l-cny',
          assetId: 'X',
          remainingQuantity: d('1'),
          costPerUnit: d('1'),
          currency: 'CNY',
        ),
      ];
      expect(
        () => computer.snapshot(
          lots: lots,
          asOf: DateTime.utc(2026, 4, 1),
          prices: InMemoryHoldingPriceSource(const []),
          converter: _identityConverter(),
          baseCurrency: 'USD',
        ),
        throwsStateError,
      );
    });
  });

  group('HoldingComputer.snapshot — multi-currency', () {
    test('USD and CNY assets get folded into a single base-currency '
        'view via the FX converter', () {
      final computer = HoldingComputer(
        engine: CostBasisEngine.forMethod(CostBasisMethod.fifo),
      );
      final lots = [
        makeLot(
          id: 'l-aapl',
          assetId: 'AAPL',
          originalQuantity: d('10'),
          remainingQuantity: d('10'),
          costPerUnit: d('100'),
          currency: 'USD',
        ),
        makeLot(
          id: 'l-600519',
          assetId: '600519',
          originalQuantity: d('100'),
          remainingQuantity: d('100'),
          costPerUnit: d('700'),
          currency: 'CNY',
        ),
      ];
      // 1 CNY = 0.125 USD (1 USD = 8 CNY) — store the CNY→USD direction
      // directly so the converter doesn't have to invert and round.
      final converter = FxRateCurrencyConverter(
        InMemoryFxRateLookup([
          FxRate(
            base: 'CNY',
            quote: 'USD',
            rate: d('0.125'),
            date: DateTime.utc(2026, 4, 1),
            source: 'test',
          ),
        ]),
      );
      final prices = InMemoryHoldingPriceSource([
        HoldingPriceObservation(
          assetId: 'AAPL',
          price: d('150'),
          currency: 'USD',
          asOf: DateTime.utc(2026, 4, 1),
        ),
        HoldingPriceObservation(
          assetId: '600519',
          price: d('1400'),
          currency: 'CNY',
          asOf: DateTime.utc(2026, 4, 1),
        ),
      ]);
      final result = computer.snapshot(
        lots: lots,
        asOf: DateTime.utc(2026, 4, 1),
        prices: prices,
        converter: converter,
        baseCurrency: 'USD',
      );

      // AAPL: native MV = 10 * 150 = 1500 USD; cost = 1000 USD; pnl = 500.
      final aapl = result['AAPL']!;
      expect(aapl.marketValueInAssetCurrency, d('1500'));
      expect(aapl.costBasisInBase, d('1000'));
      expect(aapl.marketValueInBase, d('1500'));

      // 600519: native MV = 100 * 1400 = 140,000 CNY; cost = 70,000 CNY.
      // USD: MV = 140000 * 0.125 = 17,500; cost = 70000 * 0.125 = 8,750.
      final mt = result['600519']!;
      expect(mt.marketValueInAssetCurrency, d('140000'));
      expect(mt.costBasisInBase, d('8750'));
      expect(mt.marketValueInBase, d('17500'));
      expect(mt.unrealizedPnlInBase, d('8750'));

      // Weights: total = 1500 + 17500 = 19000 USD.
      expect((aapl.weight + mt.weight).toDouble(), closeTo(1.0, 1e-7));
      expect(aapl.weight < mt.weight, isTrue);
    });
  });
}
