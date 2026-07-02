import 'package:decimal/decimal.dart';

/// Corporate actions that adjust open lots and/or generate cash flows.
///
/// - [CashDividendAction] handles 现金分红: cash lands in the account at
///   [amountPerShare] times shares held on [effectiveDate]. Open lots are
///   not modified — only a [CashDividend] record is produced.
/// - [StockDividendAction] handles 送股 / 红股 / bonus shares: existing lots
///   receive `bonusRatio` new shares per held share at zero marginal cost.
///   Quantity is scaled by `1 + bonusRatio` and `costPerUnit` is scaled
///   inversely so total cost is preserved.
/// - [SplitAction] handles 拆分 (forward split) and 合股 (reverse split):
///   ratio > 1 multiplies quantity (e.g. 2-for-1 split → ratio = 2),
///   ratio < 1 reduces quantity (e.g. 1-for-10 reverse split → ratio = 0.1).
///   In both cases [Lot.costPerUnit] is divided by the same ratio so the
///   total cost of the lot is preserved.
/// - [RightsIssueAction] handles 配股: shareholders subscribe to new shares
///   at a (typically discounted) price. Creates a brand-new [Lot] at the
///   subscription price — does not modify existing lots.
/// - [DripAction] handles DRIP (Dividend Reinvestment Plan): the dividend
///   payable on [effectiveDate] is paid in the form of additional shares at
///   [pricePerUnit] instead of cash. Produces a fresh [Lot] whose total
///   cost equals the net dividend reinvested.
sealed class CorporateAction {
  const CorporateAction({
    required this.id,
    required this.assetId,
    required this.effectiveDate,
  });

  final String id;
  final String assetId;
  final DateTime effectiveDate;
}

class CashDividendAction extends CorporateAction {
  const CashDividendAction({
    required super.id,
    required super.assetId,
    required super.effectiveDate,
    required this.transactionId,
    required this.accountId,
    required this.currency,
    required this.amountPerShare,
    required this.withholdingTax,
  });

  /// ID of the resulting cash transaction (for round-trip with the Tx ledger).
  final String transactionId;
  final String accountId;
  final String currency;

  /// Gross dividend per share, before tax. Must be non-negative.
  final Decimal amountPerShare;

  /// Total amount withheld at source across all shares (e.g. dividend tax).
  /// Subtracted from gross to compute the net cash inflow. Must be
  /// non-negative and ≤ gross.
  final Decimal withholdingTax;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CashDividendAction &&
        other.id == id &&
        other.assetId == assetId &&
        other.effectiveDate == effectiveDate &&
        other.transactionId == transactionId &&
        other.accountId == accountId &&
        other.currency == currency &&
        other.amountPerShare == amountPerShare &&
        other.withholdingTax == withholdingTax;
  }

  @override
  int get hashCode => Object.hash(
    id,
    assetId,
    effectiveDate,
    transactionId,
    accountId,
    currency,
    amountPerShare,
    withholdingTax,
  );
}

class SplitAction extends CorporateAction {
  const SplitAction({
    required super.id,
    required super.assetId,
    required super.effectiveDate,
    required this.ratio,
  });

  final Decimal ratio;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SplitAction &&
        other.id == id &&
        other.assetId == assetId &&
        other.effectiveDate == effectiveDate &&
        other.ratio == ratio;
  }

  @override
  int get hashCode => Object.hash(id, assetId, effectiveDate, ratio);
}

class StockDividendAction extends CorporateAction {
  const StockDividendAction({
    required super.id,
    required super.assetId,
    required super.effectiveDate,
    required this.bonusRatio,
  });

  final Decimal bonusRatio;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is StockDividendAction &&
        other.id == id &&
        other.assetId == assetId &&
        other.effectiveDate == effectiveDate &&
        other.bonusRatio == bonusRatio;
  }

  @override
  int get hashCode => Object.hash(id, assetId, effectiveDate, bonusRatio);
}

class RightsIssueAction extends CorporateAction {
  const RightsIssueAction({
    required super.id,
    required super.assetId,
    required super.effectiveDate,
    required this.transactionId,
    required this.accountId,
    required this.currency,
    required this.subscribedQuantity,
    required this.pricePerUnit,
    required this.fee,
  });

  final String transactionId;
  final String accountId;
  final String currency;
  final Decimal subscribedQuantity;
  final Decimal pricePerUnit;
  final Decimal fee;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RightsIssueAction &&
        other.id == id &&
        other.assetId == assetId &&
        other.effectiveDate == effectiveDate &&
        other.transactionId == transactionId &&
        other.accountId == accountId &&
        other.currency == currency &&
        other.subscribedQuantity == subscribedQuantity &&
        other.pricePerUnit == pricePerUnit &&
        other.fee == fee;
  }

  @override
  int get hashCode => Object.hash(
    id,
    assetId,
    effectiveDate,
    transactionId,
    accountId,
    currency,
    subscribedQuantity,
    pricePerUnit,
    fee,
  );
}

class DripAction extends CorporateAction {
  const DripAction({
    required super.id,
    required super.assetId,
    required super.effectiveDate,
    required this.transactionId,
    required this.accountId,
    required this.currency,
    required this.amountPerShare,
    required this.pricePerUnit,
    required this.withholdingTax,
    required this.fee,
  });

  /// ID of the resulting reinvestment transaction.
  final String transactionId;
  final String accountId;
  final String currency;

  /// Gross dividend per share. Must be positive.
  final Decimal amountPerShare;

  /// Reinvestment price per share. Must be positive.
  final Decimal pricePerUnit;

  /// Total tax withheld across all shares (deducted from gross before
  /// reinvestment). Must be non-negative.
  final Decimal withholdingTax;

  /// Broker reinvestment fee (rare for true DRIPs but supported). Must be
  /// non-negative. Baked into the new lot's [Lot.costPerUnit].
  final Decimal fee;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DripAction &&
        other.id == id &&
        other.assetId == assetId &&
        other.effectiveDate == effectiveDate &&
        other.transactionId == transactionId &&
        other.accountId == accountId &&
        other.currency == currency &&
        other.amountPerShare == amountPerShare &&
        other.pricePerUnit == pricePerUnit &&
        other.withholdingTax == withholdingTax &&
        other.fee == fee;
  }

  @override
  int get hashCode => Object.hash(
    id,
    assetId,
    effectiveDate,
    transactionId,
    accountId,
    currency,
    amountPerShare,
    pricePerUnit,
    withholdingTax,
    fee,
  );
}
