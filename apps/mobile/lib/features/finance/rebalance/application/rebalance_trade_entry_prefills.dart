import 'package:decimal/decimal.dart';

import '../../../investment/domain/trade_entry/trade_draft.dart';
import '../../../investment/domain/trade_entry/trade_entry_prefill.dart';
import '../domain/rebalance_models.dart';

typedef RebalanceTradeNoteBuilder = String Function(SuggestedTrade trade);

List<TradeEntryPrefill> buildRebalanceTradeEntryPrefills({
  required RebalancePlan plan,
  required DateTime tradeDate,
  required RebalanceTradeNoteBuilder noteBuilder,
}) {
  final totalTradeAmount = plan.trades.fold<Decimal>(
    Decimal.zero,
    (sum, trade) => sum + trade.amount.amount,
  );
  final totalSellAmount = plan.trades
      .where((trade) => trade.isSell)
      .fold<Decimal>(Decimal.zero, (sum, trade) => sum + trade.amount.amount);

  return [
    for (final trade in plan.trades)
      TradeEntryPrefill(
        type: trade.isBuy ? TradeType.buy : TradeType.sell,
        quantity: Decimal.one,
        price: trade.amount.amount,
        currency: trade.amount.currency,
        tradeDate: tradeDate,
        fee: _allocated(
          total: plan.estimatedFees.amount,
          basis: trade.amount.amount,
          denominator: totalTradeAmount,
        ),
        tax: trade.isSell
            ? _allocated(
                total: plan.estimatedTaxes.amount,
                basis: trade.amount.amount,
                denominator: totalSellAmount,
              )
            : Decimal.zero,
        note: noteBuilder(trade),
      ),
  ];
}

Decimal _allocated({
  required Decimal total,
  required Decimal basis,
  required Decimal denominator,
}) {
  if (total == Decimal.zero || basis == Decimal.zero) return Decimal.zero;
  if (denominator == Decimal.zero) return Decimal.zero;
  return (total * basis / denominator).toDecimal(scaleOnInfinitePrecision: 16);
}
