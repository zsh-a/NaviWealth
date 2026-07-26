import 'package:decimal/decimal.dart';

import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/finance/market/domain/asset_market.dart';

const Object _unsetApprovedUnderlyingField = Object();

/// An underlying symbol the user has explicitly approved for options income
/// strategies.
///
/// Hard architectural rule (`docs/domains/options-income.md` §1.2): sell put / covered
/// call candidates are only ever generated against symbols on this list.
/// LLMs cannot bypass it — the scoring engine drops any candidate whose
/// underlying is missing or has the matching strategy disabled.
///
/// `allowPut` / `allowCall` are independent so a user can, for example,
/// happily sell covered calls on a position they wouldn't want to buy more
/// of via a cash-secured put.
class ApprovedUnderlying {
  const ApprovedUnderlying({
    required this.id,
    required this.symbol,
    required this.market,
    required this.allowPut,
    required this.allowCall,
    required this.maxBuyPrice,
    required this.minSellPrice,
    this.maxPositionWeight,
    required this.notes,
    required this.sync,
  });

  /// Composite id `<market>:<symbol>` — same grammar as `Asset.idFor`.
  final String id;
  final String symbol;
  final AssetMarket market;

  /// Eligible for cash-secured puts (user willing to buy at `maxBuyPrice`).
  final bool allowPut;

  /// Eligible for covered calls (user willing to sell at `minSellPrice`).
  final bool allowCall;

  /// Price ceiling the user is comfortable paying if assigned. Drives the
  /// "would I actually want this trade?" check in the scorer. Optional —
  /// when null the scorer only enforces the strike-vs-current-price
  /// distance from the profile delta bounds.
  final Decimal? maxBuyPrice;

  /// Price floor the user is willing to be called away at. Same logic as
  /// above but on the covered-call side.
  final Decimal? minSellPrice;
  final Decimal? maxPositionWeight;

  final String? notes;

  final SyncMeta sync;

  String get displaySymbol => symbol.toUpperCase();

  static String idFor({required AssetMarket market, required String symbol}) =>
      '${market.wire}:${symbol.trim().toUpperCase()}';

  ApprovedUnderlying copyWith({
    bool? allowPut,
    bool? allowCall,
    Object? maxBuyPrice = _unsetApprovedUnderlyingField,
    Object? minSellPrice = _unsetApprovedUnderlyingField,
    Object? maxPositionWeight = _unsetApprovedUnderlyingField,
    Object? notes = _unsetApprovedUnderlyingField,
    SyncMeta? sync,
  }) {
    return ApprovedUnderlying(
      id: id,
      symbol: symbol,
      market: market,
      allowPut: allowPut ?? this.allowPut,
      allowCall: allowCall ?? this.allowCall,
      maxBuyPrice: identical(maxBuyPrice, _unsetApprovedUnderlyingField)
          ? this.maxBuyPrice
          : maxBuyPrice as Decimal?,
      minSellPrice: identical(minSellPrice, _unsetApprovedUnderlyingField)
          ? this.minSellPrice
          : minSellPrice as Decimal?,
      maxPositionWeight:
          identical(maxPositionWeight, _unsetApprovedUnderlyingField)
          ? this.maxPositionWeight
          : maxPositionWeight as Decimal?,
      notes: identical(notes, _unsetApprovedUnderlyingField)
          ? this.notes
          : notes as String?,
      sync: sync ?? this.sync,
    );
  }
}
