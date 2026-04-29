import 'package:decimal/decimal.dart';

/// A cash dividend payout. Produced by [CostBasisEngine.applyCashDividend]
/// and by [CostBasisEngine.applyDrip] (where the cash is reinvested rather
/// than received).
///
/// Dividends do not affect open lot quantity or cost basis — they are an
/// asset-side cash inflow recorded against the dividend transaction. This
/// record carries the per-share amount and the share count it was applied
/// to so downstream services (XIRR, history) can reconstruct the cash flow.
class CashDividend {
  const CashDividend({
    required this.id,
    required this.transactionId,
    required this.accountId,
    required this.assetId,
    required this.currency,
    required this.effectiveDate,
    required this.shareCount,
    required this.amountPerShare,
    required this.grossAmount,
    required this.withholdingTax,
    required this.netAmount,
    required this.reinvested,
  });

  final String id;
  final String transactionId;
  final String accountId;
  final String assetId;
  final String currency;
  final DateTime effectiveDate;

  /// Total open shares held on [effectiveDate] in [accountId] for [assetId].
  final Decimal shareCount;

  final Decimal amountPerShare;
  final Decimal grossAmount;
  final Decimal withholdingTax;

  /// Gross minus tax. For non-DRIP dividends this is the cash that lands in
  /// the account; for DRIP it is the amount that gets immediately spent on
  /// new shares.
  final Decimal netAmount;

  /// True when the dividend was paid as additional shares via DRIP. For a
  /// vanilla cash dividend this is false.
  final bool reinvested;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CashDividend &&
        other.id == id &&
        other.transactionId == transactionId &&
        other.accountId == accountId &&
        other.assetId == assetId &&
        other.currency == currency &&
        other.effectiveDate == effectiveDate &&
        other.shareCount == shareCount &&
        other.amountPerShare == amountPerShare &&
        other.grossAmount == grossAmount &&
        other.withholdingTax == withholdingTax &&
        other.netAmount == netAmount &&
        other.reinvested == reinvested;
  }

  @override
  int get hashCode => Object.hash(
    id,
    transactionId,
    accountId,
    assetId,
    currency,
    effectiveDate,
    shareCount,
    amountPerShare,
    grossAmount,
    withholdingTax,
    netAmount,
    reinvested,
  );

  @override
  String toString() =>
      'CashDividend(asset: $assetId, shares: $shareCount, '
      'gross: $grossAmount, net: $netAmount $currency, '
      'reinvested: $reinvested)';
}
