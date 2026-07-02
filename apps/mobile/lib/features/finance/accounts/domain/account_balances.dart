import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart';

/// One leg of an account's multi-currency balance — `units` worth of
/// `unit` (either an ISO currency code like `USD` / `BTC`, or an asset
/// id like `us_stock:AAPL`). Balance value is the algebraic sum of every
/// non-deleted posting on the account that uses this unit.
@immutable
class AccountBalanceLeg {
  const AccountBalanceLeg({required this.unit, required this.units});

  final String unit;
  final Decimal units;

  bool get isFiatLike => !unit.contains(':');

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AccountBalanceLeg && other.unit == unit && other.units == units;

  @override
  int get hashCode => Object.hash(unit, units);
}

/// Per-account multi-currency balance snapshot — one [AccountBalanceLeg]
/// per non-zero unit on the account. Sorted: fiat / cash legs first
/// (alphabetical), then asset legs (by id) so the UI renders a stable
/// "currencies up top, securities below" layout.
@immutable
class AccountBalances {
  const AccountBalances({required this.accountId, required this.legs});

  /// Empty snapshot for an account that has no postings yet.
  factory AccountBalances.empty(String accountId) =>
      AccountBalances(accountId: accountId, legs: const []);

  final String accountId;
  final List<AccountBalanceLeg> legs;

  /// True when more than one non-zero unit lives in this account —
  /// drives the "expandable multi-currency row" affordance.
  bool get isMultiUnit => legs.length > 1;

  bool get isEmpty => legs.isEmpty;

  /// Find the leg for a specific [unit]. Returns null when the account
  /// has never seen a posting in that unit (or the running sum is zero).
  AccountBalanceLeg? legFor(String unit) {
    for (final l in legs) {
      if (l.unit == unit) return l;
    }
    return null;
  }
}
