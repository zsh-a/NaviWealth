part of 'cost_basis_engine.dart';

void _requirePositive(Decimal value, String name) {
  if (value.sign <= 0) {
    throw ArgumentError.value(value, name, 'must be positive');
  }
}

/// Sum [Lot.remainingQuantity] across lots matching [accountId] / [assetId]
/// that were opened on or before [asOf].
Decimal _eligibleShareCount({
  required Iterable<Lot> lots,
  required String accountId,
  required String assetId,
  required DateTime asOf,
}) {
  var total = Decimal.zero;
  for (final lot in lots) {
    if (lot.accountId != accountId) continue;
    if (lot.assetId != assetId) continue;
    if (lot.openedAt.isAfter(asOf)) continue;
    total += lot.remainingQuantity;
  }
  return total;
}
