import 'package:decimal/decimal.dart';

/// Input to [CostBasisEngine.applyBuy]. The engine derives [Lot.costPerUnit]
/// as `(quantity * pricePerUnit + fee) / quantity`, baking buy-side fees
/// into the cost basis so they reduce the realized gain at sell time.
class BuyEvent {
  const BuyEvent({
    required this.transactionId,
    required this.accountId,
    required this.assetId,
    required this.currency,
    required this.quantity,
    required this.pricePerUnit,
    required this.fee,
    required this.tradeDate,
  });

  final String transactionId;
  final String accountId;
  final String assetId;
  final String currency;
  final Decimal quantity;
  final Decimal pricePerUnit;
  final Decimal fee;
  final DateTime tradeDate;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is BuyEvent &&
        other.transactionId == transactionId &&
        other.accountId == accountId &&
        other.assetId == assetId &&
        other.currency == currency &&
        other.quantity == quantity &&
        other.pricePerUnit == pricePerUnit &&
        other.fee == fee &&
        other.tradeDate == tradeDate;
  }

  @override
  int get hashCode => Object.hash(
    transactionId,
    accountId,
    assetId,
    currency,
    quantity,
    pricePerUnit,
    fee,
    tradeDate,
  );
}

/// Input to [CostBasisEngine.applySell]. Sell-side fees are recorded on the
/// resulting [RealizedPnL] records (proportionally allocated when a sell
/// spans multiple lots), not subtracted from cost basis.
class SellEvent {
  const SellEvent({
    required this.transactionId,
    required this.accountId,
    required this.assetId,
    required this.currency,
    required this.quantity,
    required this.pricePerUnit,
    required this.fee,
    required this.tradeDate,
  });

  final String transactionId;
  final String accountId;
  final String assetId;
  final String currency;
  final Decimal quantity;
  final Decimal pricePerUnit;
  final Decimal fee;
  final DateTime tradeDate;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SellEvent &&
        other.transactionId == transactionId &&
        other.accountId == accountId &&
        other.assetId == assetId &&
        other.currency == currency &&
        other.quantity == quantity &&
        other.pricePerUnit == pricePerUnit &&
        other.fee == fee &&
        other.tradeDate == tradeDate;
  }

  @override
  int get hashCode => Object.hash(
    transactionId,
    accountId,
    assetId,
    currency,
    quantity,
    pricePerUnit,
    fee,
    tradeDate,
  );
}
