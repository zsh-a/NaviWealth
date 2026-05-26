import 'package:naviwealth/features/finance/data/domain/asset.dart';
import '../values/resolved_price.dart';

/// Unified entry point for "give me a price for this asset" across the
/// synced `prices` ledger, the live `MarketDataService`, and any future
/// broker / cloud snapshot tiers.
///
/// Callers should never hit the live market service or the price
/// repository directly for valuation. Both have their place — the live
/// service still drives charts and search; the repo still receives
/// manual writes — but the *valuation* path goes through this resolver
/// so confidence and source provenance stay consistent.
abstract class PriceResolver {
  /// Resolve a single asset.
  ///
  /// [asOf] defaults to "now" (live tiers preferred). A past [asOf]
  /// disables the live tier — historical reconstruction uses ledger
  /// and historical-bar tiers only.
  ///
  /// Returns `null` only when every tier comes up empty. Callers
  /// typically fall back to cost-basis or skip the asset.
  Future<ResolvedPrice?> resolve(Asset asset, {DateTime? asOf});

  /// Batched resolve. Implementations may parallelise with bounded
  /// concurrency. Returned map always contains every input asset's id;
  /// the value is `null` for assets with no resolvable price.
  Future<Map<String, ResolvedPrice?>> resolveMany(
    Iterable<Asset> assets, {
    DateTime? asOf,
  });
}

/// Tunable thresholds for the layered resolver. Holding this in its own
/// value object means tests can shrink windows to seconds without
/// touching the resolver implementation.
class PriceResolverPolicy {
  const PriceResolverPolicy({
    this.ledgerFreshWindow = const Duration(hours: 6),
    this.liveLookback = const Duration(days: 1),
    this.historicalLookback = const Duration(days: 14),
    this.resolveManyConcurrency = 4,
  });

  /// Maximum age of a `prices` ledger row before tier 2 stops trusting
  /// it as the "fresh" source. Above this, the resolver falls through
  /// to live providers; if those fail, the same row may still serve as
  /// the stale-tier fallback (tier 5).
  final Duration ledgerFreshWindow;

  /// When [PriceResolver.resolve] is called with a past [asOf], we skip
  /// the live tier if `now - asOf` exceeds this value. Roughly: "if you
  /// asked for a price more than a day ago, you wanted history."
  final Duration liveLookback;

  /// Window the historical-bar tier sweeps backwards from [asOf] looking
  /// for the most recent daily close. 14 days covers any normal market
  /// holiday + weekend combination.
  final Duration historicalLookback;

  /// Bounded concurrency for [PriceResolver.resolveMany]. Each
  /// underlying provider has its own rate limiter, but the resolver
  /// also caps total in-flight resolves so a 200-asset portfolio
  /// doesn't fan out 200 simultaneous repo + provider calls.
  final int resolveManyConcurrency;
}
