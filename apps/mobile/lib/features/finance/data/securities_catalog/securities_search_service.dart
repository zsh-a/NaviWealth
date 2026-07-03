import 'package:drift/drift.dart' hide Column;
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/market/domain/asset_market.dart';

import 'asset_search_hit.dart';

part 'securities_search_catalog.dart';
part 'securities_search_helpers.dart';
part 'securities_search_owned.dart';

/// Strict, four-tier offline search over the local securities universe.
///
/// A fresh install with **zero** recorded trades must still find
/// the user's instrument by symbol, English name, Chinese name, full
/// pinyin or pinyin initials — and must do so without making a single
/// HTTP request. The trade-entry form calls into this service first;
/// the network-backed [MarketDataService] is only invoked when the
/// caller explicitly requests an enrichment.
///
/// Tier order (the merge is non-negotiable — never silently re-rank):
///
///   1. **Owned**   — `assets.market IS NOT NULL`, the user already
///                    holds or hand-added this instrument. Always at
///                    the top, regardless of how the row matched.
///   2. **Catalog exact** — `securities_catalog` row whose `symbol`,
///                    `name_cn`, `name_en`, `pinyin` or `pinyin_initials`
///                    equals the query (case-insensitive).
///   3. **Catalog prefix** — same columns, query is a prefix.
///   4. **Catalog FTS**    — fts5 token match (covers tokens hidden in
///                    `aliases`, multi-word substrings, etc.). Sorted by
///                    bm25 rank, low-is-better.
///
/// Any `(market, symbol)` already surfaced by tier 1 is filtered out of
/// tiers 2-4 so the user never sees a duplicate of an instrument they
/// already own.
class SecuritiesSearchService
    with SecuritiesSearchOwnedMixin, SecuritiesSearchCatalogMixin {
  SecuritiesSearchService({required AppDatabase db}) : _db = db;

  @override
  final AppDatabase _db;

  /// Run a single-string search across owned + catalog rows. Returns at
  /// most [limit] hits, ordered by tier (owned > exact > prefix > FTS)
  /// then by within-tier rank.
  ///
  /// Empty / whitespace-only [query] short-circuits to an empty list —
  /// the trade-entry UI calls this on every keystroke including the
  /// blank state, and rendering "everything" makes no sense for a
  /// 10k-row catalog.
  Future<List<AssetSearchHit>> searchLocal(
    String query, {
    int limit = 20,
    AssetMarket? market,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty || limit <= 0) return const [];
    final marketWire = market?.wire;

    final ownedHits = await _searchOwned(trimmed, marketWire, limit);
    final ownedKeys = ownedHits
        .map((h) => _MarketSymbolKey(h.market.wire, h.symbol.toLowerCase()))
        .toSet();

    if (ownedHits.length >= limit) {
      return _sortOwned(ownedHits).take(limit).toList(growable: false);
    }

    final remaining = limit - ownedHits.length;
    final catalogHits = await _searchCatalog(
      trimmed,
      marketWire,
      ownedKeys,
      remaining,
    );

    return [..._sortOwned(ownedHits), ...catalogHits];
  }
}
