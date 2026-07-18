part of 'providers.dart';

/// Device-side portfolio snapshot — the canonical holdings picture
/// (holdings engine + FX + multi-lot). Uploaded on the cloud chat path
/// (`portfolio_snapshot`) and read directly by the device `get_holdings`
/// tool, so both paths share one builder. Returns
/// `null` when the user has no holdings.
final devicePortfolioSnapshotProvider =
    FutureProvider.autoDispose<Map<String, Object?>?>(
      (ref) => buildDevicePortfolioSnapshot(ref),
    );

Future<Map<String, Object?>?> buildDevicePortfolioSnapshot(Ref ref) async {
  final holdingsFuture = ref.watch(holdingsSnapshotProvider.future);
  final assetsFuture = ref.watch(allAssetsStreamProvider.future);

  final holdings = await holdingsFuture;
  if (holdings.isEmpty) return null;
  final assets = await assetsFuture;
  final byId = {for (final asset in assets) asset.id: asset};
  final asOf = holdings.values.first.asOf.toUtc().toIso8601String();
  final baseCurrency = holdings.values.first.baseCurrency;
  return <String, Object?>{
    'as_of': asOf,
    'base_currency': baseCurrency,
    'holdings': <String, Object?>{
      for (final entry in holdings.entries)
        entry.key: holdingSnapshotJson(entry.value, byId[entry.key]),
    },
  };
}

Map<String, Object?> holdingSnapshotJson(HoldingSnapshot snap, Asset? asset) {
  return <String, Object?>{
    'asset_id': snap.assetId,
    'symbol': asset?.symbol,
    'name': asset?.name,
    'type': asset?.type.name,
    'net_quantity': snap.quantity.toString(),
    'asset_currency': snap.assetCurrency,
    'unit_price_asset_currency': snap.unitPriceInAssetCurrency?.toString(),
    'market_value_asset_currency': snap.calculatedMarketValueInAssetCurrency
        .toString(),
    'cost_basis_asset_currency': snap.costBasisInAssetCurrency.toString(),
    'base_currency': snap.baseCurrency,
    'market_value_base': snap.marketValueInBase.toString(),
    'cost_basis_base': snap.costBasisInBase.toString(),
    'unrealized_pnl_base': snap.unrealizedPnlInBase.toString(),
    'weight': snap.weight.toString(),
    'as_of': snap.asOf.toUtc().toIso8601String(),
    'price_confidence': snap.priceConfidence?.name,
    'price_source': snap.priceSource,
    'price_as_of': snap.priceAsOf?.toUtc().toIso8601String(),
  };
}

/// The canonical [HoldingSnapshot] → [AnalyticalUpload] conversion
/// (§4.3.3). Single source for the device `get_investment_performance`
/// tool, so prompt-facing tool output and local portfolio math stay
/// aligned. Decimals are stringified to avoid float drift.
AnalyticalUpload holdingSnapshotToUpload(HoldingSnapshot snap) {
  return AnalyticalUpload(
    kind: 'investment_performance',
    id: snap.assetId,
    payload: <String, Object?>{
      'asset_id': snap.assetId,
      'asset_currency': snap.assetCurrency,
      'base_currency': snap.baseCurrency,
      'as_of': snap.asOf.toUtc().toIso8601String(),
      'quantity': snap.quantity.toString(),
      'cost_basis_in_asset_currency': snap.costBasisInAssetCurrency.toString(),
      'unit_price_in_asset_currency': snap.unitPriceInAssetCurrency?.toString(),
      'market_value_in_asset_currency': snap
          .calculatedMarketValueInAssetCurrency
          .toString(),
      'cost_basis_in_base': snap.costBasisInBase.toString(),
      'market_value_in_base': snap.marketValueInBase.toString(),
      'unrealized_pnl_in_base': snap.unrealizedPnlInBase.toString(),
      'weight': snap.weight.toString(),
      'price_confidence': snap.priceConfidence?.name,
      'price_source': snap.priceSource,
      'price_as_of': snap.priceAsOf?.toUtc().toIso8601String(),
    },
  );
}
