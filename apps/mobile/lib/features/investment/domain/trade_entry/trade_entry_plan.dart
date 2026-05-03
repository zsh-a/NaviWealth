import 'package:decimal/decimal.dart';

import '../../../../data/domain/enums.dart';
import '../models/lot.dart';
import '../models/realized_pnl.dart';

/// Resolved, persistable result of a [TradeDraft].
///
/// The plan is intentionally ledger-neutral: it validates the user's input,
/// resolves the price, and computes lot effects. Persistence callers turn
/// this into `journal_entries`, `postings`, and `prices`.
class TradeEntryPlan {
  TradeEntryPlan({
    required this.trade,
    required this.pricing,
    this.createdLot,
    List<Lot>? updatedLots,
    List<RealizedPnL>? realizedPnL,
    Decimal? unfulfilledQuantity,
  }) : updatedLots = updatedLots ?? const [],
       realizedPnL = realizedPnL ?? const [],
       unfulfilledQuantity = unfulfilledQuantity ?? Decimal.zero;

  final PlannedTrade trade;
  final Lot? createdLot;
  final List<Lot> updatedLots;
  final List<RealizedPnL> realizedPnL;

  /// Quantity the sell could not fulfil from open lots. Always
  /// [Decimal.zero] in strict mode because the service throws
  /// [TradeEntryErrorCode.insufficientHoldings] before reaching this state;
  /// surfaces a value when the caller opted into permissive mode.
  final Decimal unfulfilledQuantity;

  /// Provenance of the resolved price: whether it was user-supplied or
  /// backfilled, which provider it came from, and whether an FX leg was
  /// involved.
  final PriceProvenance pricing;
}

class PlannedTrade {
  const PlannedTrade({
    required this.id,
    required this.accountId,
    required this.assetId,
    required this.type,
    required this.quantity,
    required this.price,
    required this.currency,
    required this.tradeDate,
    this.settleDate,
    this.fee,
    this.tax,
    this.counterAccountId,
    this.note,
  });

  final String id;
  final String accountId;
  final String assetId;
  final TransactionType type;
  final Decimal quantity;
  final Decimal price;
  final String currency;
  final DateTime tradeDate;
  final DateTime? settleDate;
  final Decimal? fee;
  final Decimal? tax;
  final String? counterAccountId;
  final String? note;
}

class PriceProvenance {
  const PriceProvenance({
    required this.wasBackfilled,
    this.marketSource,
    this.barAsOf,
    this.fxConverted = false,
    this.fxFromCurrency,
    this.fxRate,
    this.fxOn,
  });

  static const userSupplied = PriceProvenance(wasBackfilled: false);

  factory PriceProvenance.backfilled({
    required String source,
    required DateTime asOf,
  }) =>
      PriceProvenance(wasBackfilled: true, marketSource: source, barAsOf: asOf);

  final bool wasBackfilled;
  final String? marketSource;
  final DateTime? barAsOf;
  final bool fxConverted;
  final String? fxFromCurrency;
  final Decimal? fxRate;
  final DateTime? fxOn;
}
