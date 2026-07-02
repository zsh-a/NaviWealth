import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/domain/entities/fx_rate.dart';
import 'package:naviwealth/domain/services/currency_converter.dart';
import 'package:naviwealth/features/finance/investment/domain/cost_basis/fifo_strategy.dart';
import 'package:naviwealth/features/finance/investment/domain/cost_basis_engine.dart';
import 'package:naviwealth/features/finance/investment/domain/fx_pnl/fx_pnl_calculator.dart';
import 'package:naviwealth/features/finance/investment/domain/models/trade_events.dart';
import 'package:naviwealth/features/finance/investment/domain/models/trade_fees.dart';

import '_helpers.dart';

/// End-to-end FIR-50 sanity check: itemized fees collapse into the engine's
/// cost basis correctly, FIFO order is respected, and the resulting realized
/// records decompose into market + FX legs in the user's base currency.
void main() {
  group('Fees-into-cost FIFO with itemized TradeFees', () {
    test('A-share buy fees baked into costPerUnit; sell fees prorated', () {
      final ids = SequenceIds('lot');
      final engine = CostBasisEngine(
        strategy: const FifoStrategy(),
        idGenerator: ids.next,
      );

      // Buy 1000 shares @ 10 CNY = 10000 CNY notional.
      // Buy fees: commission 5, regulatory 0.20, transfer 0.10 — total 5.30.
      // No stamp duty on A-share buys.
      final buyFees = TradeFees(
        commission: d('5'),
        regulatory: d('0.20'),
        transferFee: d('0.10'),
      );
      expect(buyFees.total, d('5.30'));

      final lot = engine.applyBuy(
        BuyEvent(
          transactionId: 'tx-buy',
          accountId: 'a',
          assetId: '600519',
          currency: 'CNY',
          quantity: d('1000'),
          pricePerUnit: d('10'),
          fee: buyFees.total,
          tradeDate: DateTime.utc(2026, 2, 1),
        ),
      );
      // costPerUnit = (1000*10 + 5.30) / 1000 = 10.0053
      expect(lot.costPerUnit, d('10.0053'));
      expect(lot.remainingQuantity, d('1000'));

      // Sell 400 shares @ 12 CNY = 4800 CNY notional.
      // Sell fees: commission 5, stamp duty 2.40 (0.05% * 4800), reg 0.10,
      // transfer 0.04 — total 7.54.
      final sellFees = TradeFees(
        commission: d('5'),
        stampDuty: d('2.40'),
        regulatory: d('0.10'),
        transferFee: d('0.04'),
      );
      expect(sellFees.total, d('7.54'));

      final result = engine.applySell(
        SellEvent(
          transactionId: 'tx-sell',
          accountId: 'a',
          assetId: '600519',
          currency: 'CNY',
          quantity: d('400'),
          pricePerUnit: d('12'),
          fee: sellFees.total,
          tradeDate: DateTime.utc(2026, 3, 1),
        ),
        [lot],
      );

      // Single-lot consumption → all sell fees attribute to the only record.
      expect(result.realizedPnL, hasLength(1));
      final r = result.realizedPnL.single;
      expect(r.quantity, d('400'));
      expect(r.proceeds, d('4800'));
      expect(r.fees, d('7.54'));
      // costBasis = 400 * 10.0053 = 4002.12
      expect(r.costBasis, d('4002.12'));
      // gain = proceeds - fees - cost = 4800 - 7.54 - 4002.12 = 790.34
      expect(r.gain, d('790.34'));
      // lotOpenedAt is preserved for downstream FX/tax calculations.
      expect(r.lotOpenedAt, DateTime.utc(2026, 2, 1));
    });

    test('FIFO consumption across two lots with prorated sell-side fees', () {
      final ids = SequenceIds('lot');
      final engine = CostBasisEngine(
        strategy: const FifoStrategy(),
        idGenerator: ids.next,
      );

      // Older lot: 100 shares, cost 10, fee 1 baked in → costPerUnit 10.01.
      final older = engine.applyBuy(
        BuyEvent(
          transactionId: 'tx-buy-1',
          accountId: 'a',
          assetId: 'X',
          currency: 'USD',
          quantity: d('100'),
          pricePerUnit: d('10'),
          fee: d('1'),
          tradeDate: DateTime.utc(2026, 1, 1),
        ),
      );
      // Newer lot: 100 shares, cost 12, fee 2 baked in → costPerUnit 12.02.
      final newer = engine.applyBuy(
        BuyEvent(
          transactionId: 'tx-buy-2',
          accountId: 'a',
          assetId: 'X',
          currency: 'USD',
          quantity: d('100'),
          pricePerUnit: d('12'),
          fee: d('2'),
          tradeDate: DateTime.utc(2026, 2, 1),
        ),
      );

      // Sell 150 shares @ $20, total sell fee $9 — FIFO drains older (100)
      // entirely and consumes 50 of newer.
      final result = engine.applySell(
        SellEvent(
          transactionId: 'tx-sell',
          accountId: 'a',
          assetId: 'X',
          currency: 'USD',
          quantity: d('150'),
          pricePerUnit: d('20'),
          fee: d('9'),
          tradeDate: DateTime.utc(2026, 3, 1),
        ),
        [older, newer],
      );

      expect(result.realizedPnL, hasLength(2));
      // First record: 100 of older lot. Fees 100/150 * 9 = 6.
      final first = result.realizedPnL[0];
      expect(first.lotId, older.id);
      expect(first.quantity, d('100'));
      expect(first.fees, d('6'));
      // gain = 100*20 - 6 - 100*10.01 = 2000 - 6 - 1001 = 993
      expect(first.gain, d('993'));
      expect(first.lotOpenedAt, older.openedAt);

      // Second record: 50 of newer. Fees 50/150 * 9 = 3.
      final second = result.realizedPnL[1];
      expect(second.lotId, newer.id);
      expect(second.quantity, d('50'));
      expect(second.fees, d('3'));
      // gain = 50*20 - 3 - 50*12.02 = 1000 - 3 - 601 = 396
      expect(second.gain, d('396'));
      expect(second.lotOpenedAt, newer.openedAt);

      // Older lot fully consumed; newer has 50 left.
      final updatedOlder = result.updatedLots.firstWhere(
        (l) => l.id == older.id,
      );
      final updatedNewer = result.updatedLots.firstWhere(
        (l) => l.id == newer.id,
      );
      expect(updatedOlder.remainingQuantity, Decimal.zero);
      expect(updatedNewer.remainingQuantity, d('50'));
    });
  });

  group('Cross-currency buy / sell with FX P&L decomposition', () {
    final buyDate = DateTime.utc(2026, 1, 1);
    final sellDate = DateTime.utc(2026, 6, 1);

    CurrencyConverter cnyFromUsd(String openRate, String sellRate) {
      return FxRateCurrencyConverter(
        InMemoryFxRateLookup([
          FxRate(
            base: 'USD',
            quote: 'CNY',
            date: buyDate,
            rate: Decimal.parse(openRate),
            source: 'test',
          ),
          FxRate(
            base: 'USD',
            quote: 'CNY',
            date: sellDate,
            rate: Decimal.parse(sellRate),
            source: 'test',
          ),
        ]),
      );
    }

    test('USD-denominated round trip with FX appreciation: realized P&L '
        'splits cleanly into market and FX legs', () {
      final ids = SequenceIds('lot');
      final engine = CostBasisEngine(
        strategy: const FifoStrategy(),
        idGenerator: ids.next,
      );

      final buyFees = TradeFees(commission: d('1'), regulatory: d('0.05'));
      final sellFees = TradeFees(
        commission: d('1'),
        regulatory: d('0.05'),
        transferFee: d('0.02'),
      );

      // Buy 100 AAPL @ $150; fees baked in.
      final lot = engine.applyBuy(
        BuyEvent(
          transactionId: 'tx-buy',
          accountId: 'a',
          assetId: 'AAPL',
          currency: 'USD',
          quantity: d('100'),
          pricePerUnit: d('150'),
          fee: buyFees.total, // 1.05
          tradeDate: buyDate,
        ),
      );
      // costPerUnit = (100*150 + 1.05) / 100 = 150.0105
      expect(lot.costPerUnit, d('150.0105'));

      // Sell 100 AAPL @ $170; sell fees on the realized record.
      final result = engine.applySell(
        SellEvent(
          transactionId: 'tx-sell',
          accountId: 'a',
          assetId: 'AAPL',
          currency: 'USD',
          quantity: d('100'),
          pricePerUnit: d('170'),
          fee: sellFees.total, // 1.07
          tradeDate: sellDate,
        ),
        [lot],
      );
      final r = result.realizedPnL.single;
      // costBasis = 100 * 150.0105 = 15001.05; gain = 17000 - 1.07 - 15001.05
      // = 1997.88 USD
      expect(r.gain, d('1997.88'));
      expect(r.currency, 'USD');

      // FX P&L: USD strengthened from 7.0 → 7.5 between buy and sell.
      final converter = cnyFromUsd('7.00', '7.50');
      final calc = FxPnLCalculator(converter: converter, baseCurrency: 'CNY');
      final breakdown = calc.realized(r);

      // market_base = gain_usd * sell_fx = 1997.88 * 7.5 = 14984.10
      expect(breakdown.marketPnLInBase, d('14984.10'));
      // fx_base = costBasis_usd * (sell_fx - open_fx)
      //         = 15001.05 * 0.5 = 7500.525
      expect(breakdown.fxPnLInBase, d('7500.525'));
      // total = (proceeds - fees) * sell_fx - cost * open_fx
      //       = (17000 - 1.07) * 7.5 - 15001.05 * 7.0
      //       = 127491.975 - 105007.35
      //       = 22484.625
      // Cross-check: 14984.10 + 7500.525 = 22484.625 ✓
      expect(breakdown.totalPnLInBase, d('22484.625'));
    });

    test('FX depreciation can flip a USD market gain into a base loss', () {
      final ids = SequenceIds('lot');
      final engine = CostBasisEngine(
        strategy: const FifoStrategy(),
        idGenerator: ids.next,
      );

      final lot = engine.applyBuy(
        BuyEvent(
          transactionId: 'tx-buy',
          accountId: 'a',
          assetId: 'AAPL',
          currency: 'USD',
          quantity: d('100'),
          pricePerUnit: d('150'),
          fee: Decimal.zero,
          tradeDate: buyDate,
        ),
      );

      final result = engine.applySell(
        SellEvent(
          transactionId: 'tx-sell',
          accountId: 'a',
          assetId: 'AAPL',
          currency: 'USD',
          quantity: d('100'),
          pricePerUnit: d('151'), // tiny USD gain
          fee: Decimal.zero,
          tradeDate: sellDate,
        ),
        [lot],
      );
      final r = result.realizedPnL.single;
      expect(r.gain, d('100')); // 100 * (151 - 150) = $100 USD gain

      // USD weakened sharply: 7.5 → 6.5.
      final converter = cnyFromUsd('7.50', '6.50');
      final calc = FxPnLCalculator(converter: converter, baseCurrency: 'CNY');
      final breakdown = calc.realized(r);

      // market_base = 100 * 6.5 = 650 CNY
      expect(breakdown.marketPnLInBase, d('650.0'));
      // fx_base = 15000 * (6.5 - 7.5) = -15000 CNY
      expect(breakdown.fxPnLInBase, d('-15000.0'));
      // total: -14350 CNY (USD market gain wiped out by FX drop)
      expect(breakdown.totalPnLInBase, d('-14350.0'));
      expect(breakdown.totalPnLInBase.sign, -1);
    });
  });
}
