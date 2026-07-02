/// Logical market a symbol belongs to.
///
/// Used by the market-data layer to pick the right provider chain. Not the
/// same as the asset class — an A-share ETF and an A-share stock share the
/// same market routing but differ in asset class.
enum AssetMarket { cnA, hkStock, usStock, crypto, fx, unknown }

/// Stable, snake_cased wire form for [AssetMarket].
///
/// Used as the prefix in `assets.id` (`<market>:<symbol>`) and any other
/// place we persist the market across devices. The Dart `name` getter
/// produces camelCase (`cnA`), which is unstable across enum reorderings
/// and unsightly in row ids — never rely on it for storage.
extension AssetMarketWire on AssetMarket {
  String get wire {
    switch (this) {
      case AssetMarket.cnA:
        return 'cn_a';
      case AssetMarket.hkStock:
        return 'hk_stock';
      case AssetMarket.usStock:
        return 'us_stock';
      case AssetMarket.crypto:
        return 'crypto';
      case AssetMarket.fx:
        return 'fx';
      case AssetMarket.unknown:
        return 'unknown';
    }
  }
}

/// Inverse of [AssetMarketWire.wire]. Returns `null` for any input that is
/// not one of the canonical wire labels — callers decide whether to coerce
/// to [AssetMarket.unknown] or surface an error.
AssetMarket? assetMarketFromWire(String? wire) {
  if (wire == null) return null;
  switch (wire) {
    case 'cn_a':
      return AssetMarket.cnA;
    case 'hk_stock':
      return AssetMarket.hkStock;
    case 'us_stock':
      return AssetMarket.usStock;
    case 'crypto':
      return AssetMarket.crypto;
    case 'fx':
      return AssetMarket.fx;
    case 'unknown':
      return AssetMarket.unknown;
  }
  return null;
}

/// Heuristic that infers the [AssetMarket] for a bare symbol string. Used
/// by the trade-entry path when a search result lacks an explicit market.
///
/// Rules (tried in order):
///   - 6-digit numeric → [AssetMarket.cnA]
///   - `^[0-9]{4,5}\.HK$` or any `.HK` suffix → [AssetMarket.hkStock]
///   - `^[A-Z]+-USD$` → [AssetMarket.crypto] (Yahoo-style crypto pair)
///   - `^[A-Z]+$` → [AssetMarket.usStock]
///   - anything else → [AssetMarket.unknown]
///
/// Symbols are matched case-sensitively after trimming. Callers normalise
/// case before persisting.
AssetMarket inferAssetMarket(String symbol) {
  final s = symbol.trim();
  if (s.isEmpty) return AssetMarket.unknown;
  if (RegExp(r'^\d{6}$').hasMatch(s)) return AssetMarket.cnA;
  if (RegExp(r'^\d{4,5}\.HK$', caseSensitive: false).hasMatch(s) ||
      s.toUpperCase().endsWith('.HK')) {
    return AssetMarket.hkStock;
  }
  if (RegExp(r'^[A-Z]+-USD$').hasMatch(s)) return AssetMarket.crypto;
  if (RegExp(r'^[A-Z]+$').hasMatch(s)) return AssetMarket.usStock;
  return AssetMarket.unknown;
}
