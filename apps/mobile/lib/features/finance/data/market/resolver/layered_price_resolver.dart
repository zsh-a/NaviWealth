import 'package:naviwealth/core/logging/app_logger.dart';
import 'package:naviwealth/features/finance/data/market/exceptions.dart';
import 'package:naviwealth/features/finance/data/market/http/clock.dart';
import 'package:naviwealth/features/finance/data/repositories/price_repository.dart';
import 'package:naviwealth/features/finance/domain/models/asset.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/market/domain/asset_market.dart';
import 'package:naviwealth/features/finance/market/domain/historical_bar.dart';
import 'package:naviwealth/features/finance/market/domain/market_data_service.dart';
import 'package:naviwealth/features/finance/market/domain/price_confidence.dart';
import 'package:naviwealth/features/finance/market/domain/quote.dart';
import 'package:naviwealth/features/finance/market/domain/resolved_price.dart';

import 'price_resolver.dart';

/// Default [PriceResolver] implementation. Walks a fixed tier order and
/// returns the first non-null result.
///
/// Tier order (top wins):
///   1. Broker — currently no-op; the [BrokerPriceSource] interface is the
///      seam for a future direct-broker integration.
///   2. Manual ledger price — an explicit user valuation always wins.
///   3. Live quote — composite market service. Skipped when [asOf] is too far
///      in the past or the asset has no quotable symbol.
///   4. Ledger (fresh) — recent auto snapshots are an offline fallback after
///      the live provider, never a reason to freeze an intraday valuation.
///   5. Historical bar — most recent daily close within
///      [PriceResolverPolicy.historicalLookback].
///   6. Ledger (stale) — last-known row, downgraded to [PriceConfidence.stale].
///
/// Cross-device cache note: Phase E daily-close write-back stores
/// `auto:<provider>` rows in the synced `prices` ledger. Those rows flow
/// through the fresh/stale ledger tiers above; there is no separate cloud
/// snapshot tier in the device resolver.
///
/// The class is plain Dart with constructor injection; Riverpod owns wiring.
class LayeredPriceResolver implements PriceResolver {
  LayeredPriceResolver({
    required MarketDataService market,
    required PriceRepository prices,
    Clock clock = const SystemClock(),
    PriceResolverPolicy policy = const PriceResolverPolicy(),
    BrokerPriceSource? broker,
  }) : _market = market,
       _prices = prices,
       _clock = clock,
       _policy = policy,
       _broker = broker;

  final MarketDataService _market;
  final PriceRepository _prices;
  final Clock _clock;
  final PriceResolverPolicy _policy;
  final BrokerPriceSource? _broker;

  @override
  Future<ResolvedPrice?> resolve(Asset asset, {DateTime? asOf}) async {
    final now = _clock.now();
    final at = asOf ?? now;

    final brokerHit = await _brokerTier(asset, at);
    if (brokerHit != null) return brokerHit;

    final freshLedger = await _ledgerFreshTier(asset, at);
    if (freshLedger?.confidence == PriceConfidence.manual) return freshLedger;

    final live = await _liveQuoteTier(asset, at, now);
    if (live != null) return live;

    if (freshLedger != null) return freshLedger;

    final bar = await _historicalBarTier(asset, at);
    if (bar != null) return bar;

    final staleLedger = await _ledgerStaleTier(asset, at);
    if (staleLedger != null) return staleLedger;

    return null;
  }

  @override
  Future<Map<String, ResolvedPrice?>> resolveMany(
    Iterable<Asset> assets, {
    DateTime? asOf,
  }) async {
    final input = assets.toList(growable: false);
    final result = <String, ResolvedPrice?>{};
    final concurrency = _policy.resolveManyConcurrency.clamp(1, 64);
    for (var i = 0; i < input.length; i += concurrency) {
      final end = (i + concurrency < input.length)
          ? i + concurrency
          : input.length;
      final batch = input.sublist(i, end);
      final resolved = await Future.wait(
        batch.map((a) => resolve(a, asOf: asOf)),
      );
      for (var j = 0; j < batch.length; j++) {
        result[batch[j].id] = resolved[j];
      }
    }
    return result;
  }

  // ---------- Tier 1: Broker (future seam) ----------

  Future<ResolvedPrice?> _brokerTier(Asset asset, DateTime asOf) async {
    final broker = _broker;
    if (broker == null) return null;
    try {
      return await broker.priceFor(asset, asOf: asOf);
    } catch (e, st) {
      AppLogger.instance.w('broker tier failed for ${asset.id}: $e\n$st');
      return null;
    }
  }

  // ---------- Tier 2: Ledger (fresh) ----------

  Future<ResolvedPrice?> _ledgerFreshTier(Asset asset, DateTime asOf) async {
    final obs = await _prices.latestAt(
      unit: asset.id,
      quoteCurrency: asset.currency,
      asOf: asOf,
    );
    if (obs == null) return null;
    final age = asOf.difference(obs.observedOn);
    if (age.isNegative || age > _policy.ledgerFreshWindow) return null;
    return ResolvedPrice(
      value: obs.perUnit,
      currency: obs.quoteCurrency,
      confidence: _confidenceForLedgerSource(obs.source),
      source: obs.source,
      asOf: obs.observedOn,
      fetchedAt: obs.sync.updatedAt,
    );
  }

  // ---------- Tier 3: Live quote ----------

  Future<ResolvedPrice?> _liveQuoteTier(
    Asset asset,
    DateTime asOf,
    DateTime now,
  ) async {
    if (!_assetSupportsLive(asset)) return null;
    final lookback = now.difference(asOf);
    if (!lookback.isNegative && lookback > _policy.liveLookback) return null;

    final market = assetMarketFromWire(asset.market);
    final MarketResponse<Quote> resp;
    try {
      resp = await _market.getQuote(asset.symbol, market: market);
    } on NoMarketDataAvailableException catch (e) {
      AppLogger.instance.d('live tier: no data for ${asset.symbol}: $e');
      return null;
    } on MarketDataException catch (e) {
      AppLogger.instance.w('live tier: ${asset.symbol}: $e');
      return null;
    }

    final age = now.difference(resp.data.asOf);
    final confidence = PriceConfidenceMapping.fromFreshness(
      resp.freshness,
      age: age.isNegative ? Duration.zero : age,
      market: market,
    );
    return ResolvedPrice(
      value: resp.data.price,
      currency: resp.data.currency,
      confidence: confidence,
      source: resp.source,
      asOf: resp.data.asOf,
      fetchedAt: resp.fetchedAt,
    );
  }

  // ---------- Tier 5: Historical bar ----------

  Future<ResolvedPrice?> _historicalBarTier(Asset asset, DateTime asOf) async {
    if (!_assetSupportsHistorical(asset)) return null;
    final from = asOf.subtract(_policy.historicalLookback);
    final market = assetMarketFromWire(asset.market);
    final MarketResponse<List<HistoricalBar>> resp;
    try {
      resp = await _market.getHistorical(
        asset.symbol,
        from: from,
        to: asOf,
        market: market,
      );
    } on NoMarketDataAvailableException catch (e) {
      AppLogger.instance.d('bar tier: no data for ${asset.symbol}: $e');
      return null;
    } on MarketDataException catch (e) {
      AppLogger.instance.w('bar tier: ${asset.symbol}: $e');
      return null;
    }
    final bars = resp.data;
    if (bars.isEmpty) return null;
    // Bars come back ascending; walk backwards for the latest bar <= asOf.
    HistoricalBar? pick;
    for (var i = bars.length - 1; i >= 0; i--) {
      if (!bars[i].asOf.isAfter(asOf)) {
        pick = bars[i];
        break;
      }
    }
    if (pick == null) return null;
    return ResolvedPrice(
      value: pick.adjustedClose ?? pick.close,
      currency: asset.currency,
      confidence: PriceConfidence.dailyClose,
      source: 'historical-bar:${resp.source}',
      asOf: pick.asOf,
      fetchedAt: resp.fetchedAt,
    );
  }

  // ---------- Tier 6: Ledger (stale) ----------

  Future<ResolvedPrice?> _ledgerStaleTier(Asset asset, DateTime asOf) async {
    final obs = await _prices.latestAt(
      unit: asset.id,
      quoteCurrency: asset.currency,
      asOf: asOf,
    );
    if (obs == null) return null;
    final age = asOf.difference(obs.observedOn);
    return ResolvedPrice(
      value: obs.perUnit,
      currency: obs.quoteCurrency,
      confidence: PriceConfidence.stale,
      source: obs.source,
      asOf: obs.observedOn,
      fetchedAt: obs.sync.updatedAt,
      note: 'forward-filled ${age.inDays}d',
    );
  }

  // ---------- Helpers ----------

  PriceConfidence _confidenceForLedgerSource(String source) {
    final lower = source.toLowerCase();
    if (lower == 'manual' || lower.startsWith('manual:')) {
      return PriceConfidence.manual;
    }
    return PriceConfidence.dailyClose;
  }

  /// Manual-valuation asset types (cash, deposits, wealth products) have no
  /// quotable symbol — skip the live tier without burning a network call.
  /// Same logic applies to free-form types (custom, commodity) whose symbol
  /// may be a label, not a ticker.
  bool _assetSupportsLive(Asset asset) {
    if (kManualValuationAssetTypes.contains(asset.type)) return false;
    if (asset.type == AssetType.custom) return false;
    if (asset.symbol.trim().isEmpty) return false;
    return true;
  }

  bool _assetSupportsHistorical(Asset asset) {
    if (!_assetSupportsLive(asset)) return false;
    // No provider in the current chain serves real-estate or vehicle history;
    // those route through the manual-valuation flow exclusively.
    if (asset.type == AssetType.realEstate ||
        asset.type == AssetType.vehicle ||
        asset.type == AssetType.commodity) {
      return false;
    }
    return true;
  }
}

/// Future seam: broker-direct price source (IBKR, Futu, Binance, ...).
/// Today every implementation is `null` — the interface exists so the
/// resolver compiles with `broker: someBroker` once the integration lands.
abstract class BrokerPriceSource {
  Future<ResolvedPrice?> priceFor(Asset asset, {required DateTime asOf});
}
