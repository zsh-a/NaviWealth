import 'package:decimal/decimal.dart';

/// A realized gain/loss record. One [RealizedPnL] is produced per consumed
/// lot per sell — a single sell that draws from N lots produces N records.
///
/// [lotOpenedAt] is preserved so downstream services (FX P&L, capital
/// gains tax) can resolve the buy-day FX rate or holding period without
/// having to keep the original [Lot] around after persistence.
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
    required this.lotOpenedAt,
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

  /// `Lot.openedAt` of the consumed lot. Equal to the buy date for ordinary
  /// lots; equal to the corporate-action effective date for lots opened by
  /// a rights issue or DRIP.
  final DateTime lotOpenedAt;

  /// Net realized gain in asset currency: proceeds minus fees minus cost
  /// basis. Capital-gains tax is computed against this value.
  Decimal get gain => proceeds - fees - costBasis;

  /// Elapsed time from lot open to realization. Useful as the
  /// [TaxPolicy.capitalGainsTax] holding period input.
  Duration get holdingPeriod => realizedAt.difference(lotOpenedAt);

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
        other.realizedAt == realizedAt &&
        other.lotOpenedAt == lotOpenedAt;
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
    lotOpenedAt,
  );

  @override
  String toString() =>
      'RealizedPnL(lot: $lotId, qty: $quantity, gain: $gain $currency)';
}
