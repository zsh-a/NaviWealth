import 'package:decimal/decimal.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'money.freezed.dart';

/// Pairing of a [Decimal] amount with an ISO-4217 (or crypto pseudo-)
/// currency code.
///
/// Money is intentionally **not** persisted as a single column — each
/// `Decimal` lives in its own `TEXT` column with its own currency column,
/// because (a) Drift can't pack a value object into one slot without manual
/// converters per table and (b) reporting queries need to group by currency
/// in SQL. This class is the in-memory representation only.
@freezed
class Money with _$Money {
  const factory Money({required Decimal amount, required String currency}) =
      _Money;

  static final Money zeroUsd = Money(amount: Decimal.zero, currency: 'USD');
}
