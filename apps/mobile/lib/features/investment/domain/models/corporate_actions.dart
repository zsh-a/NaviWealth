import 'package:decimal/decimal.dart';

/// Corporate actions that adjust open lots without realizing gain.
///
/// - [SplitAction] handles both 拆分 (forward split) and 合股 (reverse split):
///   ratio > 1 multiplies quantity (e.g. 2-for-1 split → ratio = 2),
///   ratio < 1 reduces quantity (e.g. 1-for-10 reverse split → ratio = 0.1).
///   In both cases [Lot.costPerUnit] is divided by the same ratio so the
///   total cost of the lot is preserved.
/// - [StockDividendAction] handles 送股 / bonus shares: existing lots receive
///   `bonusRatio` new shares per held share at zero marginal cost. Quantity
///   is scaled by `1 + bonusRatio` and `costPerUnit` is scaled inversely.
/// - [RightsIssueAction] handles 配股: shareholders subscribe to new shares
///   at a (typically discounted) price. Creates a brand-new [Lot] at the
///   subscription price — does not modify existing lots.
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
