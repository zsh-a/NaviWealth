import 'package:decimal/decimal.dart';
import 'package:naviwealth/features/investment/domain/models/lot.dart';

/// Shorthand for [Decimal.parse] used throughout the cost-basis tests.
Decimal d(String s) => Decimal.parse(s);

/// A deterministic ID generator that yields `prefix-1`, `prefix-2`, … so
/// generated IDs are predictable and tests can assert on them.
class SequenceIds {
  SequenceIds([this.prefix = 'id']);

  final String prefix;
  int _n = 0;

  String next() => '$prefix-${++_n}';
}

/// Build a [Lot] with sensible defaults so tests only set the fields that
/// matter for the assertion. [openedAt] defaults to a stable epoch + [day]
/// days, which makes age ordering trivial in FIFO/LIFO scenarios.
Lot makeLot({
  String id = 'lot-1',
  String openingTransactionId = 'tx-1',
  String accountId = 'acct-1',
  String assetId = 'asset-1',
  String currency = 'USD',
  Decimal? originalQuantity,
  Decimal? remainingQuantity,
  Decimal? costPerUnit,
  int day = 0,
}) {
  final origQty = originalQuantity ?? d('100');
  return Lot(
    id: id,
    openingTransactionId: openingTransactionId,
    accountId: accountId,
    assetId: assetId,
    currency: currency,
    originalQuantity: origQty,
    remainingQuantity: remainingQuantity ?? origQty,
    costPerUnit: costPerUnit ?? d('10'),
    openedAt: DateTime.utc(2026, 1, 1).add(Duration(days: day)),
  );
}
