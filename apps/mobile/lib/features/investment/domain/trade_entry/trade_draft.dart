import 'package:decimal/decimal.dart';

import '../../../../data/domain/asset.dart';
import '../../../../data/domain/enums.dart';

/// Operations the trade-entry service understands. Pure cash flows
/// (deposit / withdraw / fee / tax) live on [TransactionType] but never reach
/// this service — they have no asset, no lot, and no market backfill, so
/// they're handled by the cash-flow entry feature.
const Set<TransactionType> kSecurityTransactionTypes = {
  TransactionType.buy,
  TransactionType.sell,
  TransactionType.transferIn,
  TransactionType.transferOut,
  TransactionType.valuationAdjust,
};

/// Input value-object describing a trade the user is about to record.
///
/// Optional [price] is the hook for the "let the market backfill it" flow —
/// when null, the service fetches the trade-day close from
/// [MarketDataService] and substitutes it. Users can always override the
/// returned price afterwards by editing the persisted transaction.
class TradeDraft {
  const TradeDraft({
    required this.type,
    required this.asset,
    required this.accountId,
    required this.quantity,
    required this.currency,
    required this.tradeDate,
    this.price,
    this.fee = _zeroFallback,
    this.tax = _zeroFallback,
    this.counterAccountId,
    this.note,
    this.transactionId,
    this.settleDate,
  });

  /// Sentinel default used by Dart const constructors. We can't write
  /// `Decimal.zero` as a default value because [Decimal] is not a const
  /// type, so we fall back to [Decimal.zero] on field access via
  /// [feeOrZero] / [taxOrZero] helpers below.
  static const Decimal? _zeroFallback = null;

  final TransactionType type;
  final Asset asset;
  final String accountId;
  final Decimal quantity;
  final Decimal? price;
  final String currency;
  final DateTime tradeDate;
  final DateTime? settleDate;
  final Decimal? fee;
  final Decimal? tax;
  final String? counterAccountId;
  final String? note;

  /// Optional override for the generated transaction id. When omitted, the
  /// service generates a fresh UUIDv4. Useful when the caller already has an
  /// id reserved (e.g. for retry safety on the persistence path).
  final String? transactionId;

  Decimal get feeOrZero => fee ?? Decimal.zero;
  Decimal get taxOrZero => tax ?? Decimal.zero;

  bool get isSecurityTrade => kSecurityTransactionTypes.contains(type);
}
