import 'package:decimal/decimal.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../domain/values/asset_market.dart';
import 'enums.dart';
import 'sync_meta.dart';

part 'asset.freezed.dart';

@freezed
class Asset with _$Asset {
  // Required by freezed to host the static [idFor] helper alongside the
  // generated factory.
  const Asset._();

  const factory Asset({
    required String id,
    required AssetType type,
    required String symbol,
    required String currency,
    String? name,
    String? market,
    String? industry,
    String? region,
    String? isin,
    Decimal? lastPrice,
    DateTime? lastPriceAt,
    String? logoUrl,
    String? metadataJson,
    required SyncMeta sync,
  }) = _Asset;

  /// Canonical id for a securities-class asset (FIR-75): `<market>:<symbol>`.
  ///
  /// Securities use a deterministic id derived from `(market, symbol)` so
  /// the same instrument lines up across devices without a UUID mapping
  /// table. Manual-valuation assets (cash / deposits / wealth products)
  /// keep their UUIDs — they have no global identifier to derive from.
  ///
  /// External code MUST go through this factory rather than concatenating
  /// strings inline; that way the wire format stays in one place if the
  /// id grammar evolves.
  static String idFor(AssetMarket market, String symbol) {
    final trimmed = symbol.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(symbol, 'symbol', 'must not be empty');
    }
    if (trimmed.contains(':')) {
      // The id grammar is `<market>:<symbol>`; a colon inside the symbol
      // would let two different (market, symbol) pairs collide on id.
      throw ArgumentError.value(symbol, 'symbol', 'must not contain ":"');
    }
    return '${market.wire}:$trimmed';
  }
}
