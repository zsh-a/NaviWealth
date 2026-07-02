import 'asset_market.dart';

/// A search-result row for symbol lookup.
class SymbolInfo {
  const SymbolInfo({
    required this.symbol,
    required this.name,
    required this.market,
    this.currency,
    this.exchange,
    this.assetType,
  });

  final String symbol;
  final String name;
  final AssetMarket market;
  final String? currency;
  final String? exchange;

  /// Free-form provider-supplied tag (e.g. EQUITY, ETF, INDEX, CRYPTO).
  final String? assetType;
}
