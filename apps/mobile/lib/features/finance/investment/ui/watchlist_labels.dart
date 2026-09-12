import 'package:flutter/widgets.dart';
import 'package:naviwealth/features/finance/market/domain/asset_market.dart';
import 'package:naviwealth/features/finance/market/domain/market_data_service.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../data/watchlist_repository.dart';

/// Human label for a market, shared by every watchlist surface.
String watchlistMarketLabel(AppLocalizations l10n, AssetMarket market) {
  return switch (market) {
    AssetMarket.cnA => l10n.watchlistMarketCnA,
    AssetMarket.hkStock => l10n.watchlistMarketHkStock,
    AssetMarket.usStock => l10n.watchlistMarketUsStock,
    AssetMarket.crypto => l10n.watchlistMarketCrypto,
    AssetMarket.fx => l10n.watchlistMarketFx,
    AssetMarket.unknown => l10n.watchlistMarketUnknown,
  };
}

/// Freshness *only when it is worth mentioning*.
///
/// A valid cache entry is still fresh. Only expired quotes need a warning.
String? watchlistStaleFreshnessLabel(
  AppLocalizations l10n,
  DataFreshness? freshness,
) => switch (freshness) {
  DataFreshness.live || DataFreshness.cachedFresh || null => null,
  DataFreshness.stale => l10n.watchlistFreshnessStale,
};

/// Markets a watchlist entry can belong to. The watchlist is the only surface
/// that lets the user narrow before searching, so the list lives here rather
/// than in the page.
const watchlistEditableMarkets = <AssetMarket>[
  AssetMarket.usStock,
  AssetMarket.hkStock,
  AssetMarket.cnA,
  AssetMarket.crypto,
  AssetMarket.fx,
];

/// Name plus ticker, falling back to the ticker alone when the catalog has no
/// localized name for the symbol.
String watchlistItemLabel(BuildContext context, WatchlistItem item) {
  final name = item.localizedName(Localizations.localeOf(context).languageCode);
  return name == null ? item.displaySymbol : '$name (${item.displaySymbol})';
}
