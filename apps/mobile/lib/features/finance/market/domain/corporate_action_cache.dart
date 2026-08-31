import 'asset_market.dart';
import 'corporate_action_provider.dart';

/// Rebuildable device-local cache for normalized public corporate actions.
///
/// Implementations must not sync these rows or project them into real
/// portfolio/ledger aggregates. An authoritative empty fetch is cached as
/// metadata even though it has no action rows.
abstract interface class CorporateActionCache {
  Future<CorporateActionFetchResult?> read({
    required String symbol,
    required AssetMarket market,
  });

  Future<void> write({
    required String symbol,
    required AssetMarket market,
    required CorporateActionFetchResult result,
  });

  Future<void> invalidate({
    required String symbol,
    required AssetMarket market,
  });
}
