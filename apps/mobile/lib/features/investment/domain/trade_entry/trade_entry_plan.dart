import 'package:decimal/decimal.dart';

import '../../../../data/domain/transaction.dart';
import '../models/lot.dart';
import '../models/realized_pnl.dart';

/// Resolved, persistable result of a [TradeDraft].
///
/// The [transaction] embeds full [SyncMeta] (so the persistence layer can
/// write straight through). [createdLot] is set when the trade opens a new
/// lot (buy / transfer-in). [updatedLots] is the post-consumption state of
/// any lots a sell drew from. [realizedPnL] is one record per consumed lot.
class TradeEntryPlan {
  TradeEntryPlan({
    required this.transaction,
    required this.pricing,
    this.createdLot,
    List<Lot>? updatedLots,
    List<RealizedPnL>? realizedPnL,
    Decimal? unfulfilledQuantity,
  })  : updatedLots = updatedLots ?? const [],
        realizedPnL = realizedPnL ?? const [],
        unfulfilledQuantity = unfulfilledQuantity ?? Decimal.zero;

  final Transaction transaction;
  final Lot? createdLot;
  final List<Lot> updatedLots;
  final List<RealizedPnL> realizedPnL;

  /// Quantity the sell could not fulfil from open lots. Always
  /// [Decimal.zero] in strict mode because the service throws
  /// [TradeEntryErrorCode.insufficientHoldings] before reaching this state;
  /// surfaces a value when the caller opted into permissive mode.
  final Decimal unfulfilledQuantity;

  /// Provenance of the price stored on [transaction]: whether it was user-
  /// supplied or backfilled, which provider it came from, and whether an
  /// FX leg was involved.
  final PriceProvenance pricing;
}

/// How the price stored on the [Transaction] was determined.
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

  /// User passed an explicit price.
  static const userSupplied = PriceProvenance(wasBackfilled: false);

  /// Backfilled from a market-data provider, no FX leg.
  factory PriceProvenance.backfilled({
    required String source,
    required DateTime asOf,
  }) =>
      PriceProvenance(
        wasBackfilled: true,
        marketSource: source,
        barAsOf: asOf,
      );

  /// True when [Transaction.price] was set from a market quote rather than
  /// the user input.
  final bool wasBackfilled;

  /// Provider tag (e.g. `yfinance`, `coingecko`) of the source bar.
  final String? marketSource;

  /// `asOf` of the historical bar we read the close from.
  final DateTime? barAsOf;

  /// True when the asset's quoted currency differed from the trade currency
  /// and we converted via [CurrencyConverter].
  final bool fxConverted;

  /// Currency the bar was originally quoted in (before conversion).
  final String? fxFromCurrency;

  /// FX rate (`fxFromCurrency` → trade currency) applied. Useful for audit
  /// trails — the user can reproduce the price if the FX rate is recorded.
  final Decimal? fxRate;

  /// Effective date the FX rate was looked up against — typically the trade
  /// date, but may be earlier if the trade-date rate was unavailable.
  final DateTime? fxOn;
}

/// Tombstone instruction returned by [TradeEntryService.buildDeletePlan].
///
/// The trade-entry service does not own persistence; it only describes the
/// delete in terms the OpLog writer understands.
class TransactionDeletePlan {
  const TransactionDeletePlan({
    required this.transactionId,
    required this.releaseLotIds,
  });

  final String transactionId;

  /// Ids of lots the original transaction created. Persistence layer will
  /// remove (or also tombstone) these so the holding view stays consistent.
  final List<String> releaseLotIds;
}
