import 'package:decimal/decimal.dart';

/// A realized gain/loss record. One [RealizedPnL] is produced per consumed
/// lot per sell — a single sell that draws from N lots produces N records.
class RealizedPnL {
  const RealizedPnL({
    required this.id,
    required this.sellTransactionId,
    required this.lotId,
    required this.accountId,
    required this.assetId,
    required this.currency,
    required this.quantity,
    required this.costBasis,
    required this.proceeds,
    required this.fees,
    required this.realizedAt,
  });

  final String id;
  final String sellTransactionId;
  final String lotId;
  final String accountId;
  final String assetId;
  final String currency;
  final Decimal quantity;
  final Decimal costBasis;
  final Decimal proceeds;
  final Decimal fees;
  final DateTime realizedAt;

  /// Net realized gain: proceeds minus fees minus cost basis.
  Decimal get gain => proceeds - fees - costBasis;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RealizedPnL &&
        other.id == id &&
        other.sellTransactionId == sellTransactionId &&
        other.lotId == lotId &&
        other.accountId == accountId &&
        other.assetId == assetId &&
        other.currency == currency &&
        other.quantity == quantity &&
        other.costBasis == costBasis &&
        other.proceeds == proceeds &&
        other.fees == fees &&
        other.realizedAt == realizedAt;
  }

  @override
  int get hashCode => Object.hash(
    id,
    sellTransactionId,
    lotId,
    accountId,
    assetId,
    currency,
    quantity,
    costBasis,
    proceeds,
    fees,
    realizedAt,
  );

  @override
  String toString() =>
      'RealizedPnL(lot: $lotId, qty: $quantity, gain: $gain $currency)';
}
