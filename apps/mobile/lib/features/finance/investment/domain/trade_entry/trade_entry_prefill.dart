import 'package:decimal/decimal.dart';
import 'package:naviwealth/features/finance/market/domain/asset_market.dart';

import 'trade_draft.dart';

/// Presentation-ready defaults for trade-entry form callers.
///
/// Upstream workflows can know the trade side and value before the user has
/// picked the exact security. They pass those values here; the form still owns
/// final asset selection and persistence through `tradeEntryServiceProvider`.
class TradeEntryPrefill {
  const TradeEntryPrefill({
    required this.type,
    required this.quantity,
    required this.currency,
    this.price,
    this.tradeDate,
    this.fee,
    this.tax,
    this.note,
    this.symbol,
    this.market,
  });

  final TradeType type;
  final Decimal quantity;
  final Decimal? price;
  final String currency;
  final DateTime? tradeDate;
  final Decimal? fee;
  final Decimal? tax;
  final String? note;
  final String? symbol;
  final AssetMarket? market;
}
