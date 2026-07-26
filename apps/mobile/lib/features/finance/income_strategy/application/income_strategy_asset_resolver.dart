import 'package:naviwealth/features/finance/domain/models/asset.dart';
import 'package:naviwealth/features/finance/income_strategy/domain/income_strategy.dart';
import 'package:naviwealth/features/finance/market/domain/asset_market.dart';

/// Resolves every sleeve onto FinanceOS's canonical `<market>:<symbol>` key.
class IncomeStrategyAssetResolver {
  IncomeStrategyAssetResolver(Iterable<Asset> assets)
    : _assetsById = {for (final asset in assets) asset.id: asset};

  final Map<String, Asset> _assetsById;

  IncomeStrategyAsset fromAssetId(
    String assetId, {
    required String fallbackCurrency,
    String? fallbackLabel,
  }) {
    final asset = _assetsById[assetId];
    final split = assetId.indexOf(':');
    final fallbackMarket = split < 0
        ? AssetMarket.unknown.wire
        : assetId.substring(0, split);
    final fallbackSymbol = split < 0 ? assetId : assetId.substring(split + 1);
    return IncomeStrategyAsset(
      assetId: assetId,
      symbol: asset?.symbol ?? fallbackSymbol,
      market: asset?.market ?? fallbackMarket,
      currency: asset?.currency ?? fallbackCurrency,
      label: asset?.name ?? fallbackLabel,
    );
  }

  IncomeStrategyAsset fromSymbol({
    required String symbol,
    required String currency,
    String? marketWire,
  }) {
    final normalized = symbol.trim().toUpperCase();
    final explicitMarket = assetMarketFromWire(marketWire);
    final market = explicitMarket ?? inferAssetMarket(normalized);
    final id = Asset.idFor(market, normalized);
    return fromAssetId(id, fallbackCurrency: currency);
  }
}
