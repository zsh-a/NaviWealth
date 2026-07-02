import 'package:decimal/decimal.dart';

/// A single buy parcel of an asset. Lots are 1:1 with the buy transaction
/// (or rights-issue subscription) that opened them. They are mutated only by
/// sells (reduce [remainingQuantity]) and corporate actions (split / stock
/// dividend / reverse-split, which adjust both quantity and [costPerUnit]
/// while preserving total cost).
class Lot {
  const Lot({
    required this.id,
    required this.openingTransactionId,
    required this.accountId,
    required this.assetId,
    required this.currency,
    required this.originalQuantity,
    required this.remainingQuantity,
    required this.costPerUnit,
    required this.openedAt,
  });

  final String id;
  final String openingTransactionId;
  final String accountId;
  final String assetId;
  final String currency;
  final Decimal originalQuantity;
  final Decimal remainingQuantity;
  final Decimal costPerUnit;
  final DateTime openedAt;

  /// True when no shares are left in this lot.
  bool get isClosed => remainingQuantity.sign <= 0;

  /// Cost basis of the still-open portion of this lot.
  Decimal get remainingCost => remainingQuantity * costPerUnit;

  /// Cost basis of the original parcel, before any sells.
  Decimal get originalCost => originalQuantity * costPerUnit;

  Lot copyWith({
    String? id,
    String? openingTransactionId,
    String? accountId,
    String? assetId,
    String? currency,
    Decimal? originalQuantity,
    Decimal? remainingQuantity,
    Decimal? costPerUnit,
    DateTime? openedAt,
  }) {
    return Lot(
      id: id ?? this.id,
      openingTransactionId: openingTransactionId ?? this.openingTransactionId,
      accountId: accountId ?? this.accountId,
      assetId: assetId ?? this.assetId,
      currency: currency ?? this.currency,
      originalQuantity: originalQuantity ?? this.originalQuantity,
      remainingQuantity: remainingQuantity ?? this.remainingQuantity,
      costPerUnit: costPerUnit ?? this.costPerUnit,
      openedAt: openedAt ?? this.openedAt,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Lot &&
        other.id == id &&
        other.openingTransactionId == openingTransactionId &&
        other.accountId == accountId &&
        other.assetId == assetId &&
        other.currency == currency &&
        other.originalQuantity == originalQuantity &&
        other.remainingQuantity == remainingQuantity &&
        other.costPerUnit == costPerUnit &&
        other.openedAt == openedAt;
  }

  @override
  int get hashCode => Object.hash(
    id,
    openingTransactionId,
    accountId,
    assetId,
    currency,
    originalQuantity,
    remainingQuantity,
    costPerUnit,
    openedAt,
  );

  @override
  String toString() =>
      'Lot(id: $id, asset: $assetId, qty: $remainingQuantity/$originalQuantity, '
      'costPerUnit: $costPerUnit, openedAt: $openedAt)';
}
