import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/market/domain/asset_market.dart';

/// Where a [AssetSearchHit] came from. Drives the UI grouping in the
/// trade-entry picker (owned rows render under a "我的资产" header,
/// catalog rows under "市场目录").
enum AssetSearchHitSource {
  /// Row materialised from `assets` — the user has either traded this
  /// instrument or hand-added it. Always ranked first.
  owned,

  /// Row from the read-only `securities_catalog` seed dictionary.
  catalog,
}

/// Why a catalog row matched. Lets the search service surface a stable
/// priority order (exact > prefix > FTS) without leaking SQL details to
/// the UI, and makes the test assertions self-describing.
enum AssetSearchHitMatch {
  /// Token / column equals the query verbatim (case-insensitive).
  exact,

  /// Token / column starts with the query.
  prefix,

  /// FTS5 token match (anywhere in the row's bag of searchable terms).
  fts,

  /// CJK substring fallback — query is non-Latin and matched as a
  /// substring of `name_cn`. Distinct from [fts] because the unicode61
  /// tokenizer treats a multi-character Han run as a single token, so
  /// `MATCH '茅台*'` against `贵州茅台` would miss without this fallback.
  cjkSubstring,
}

/// One row in the search-result list returned by
/// [SecuritiesSearchService.searchLocal].
class AssetSearchHit {
  const AssetSearchHit({
    required this.id,
    required this.symbol,
    required this.market,
    required this.type,
    required this.currency,
    required this.source,
    required this.match,
    required this.rank,
    this.nameEn,
    this.nameCn,
  });

  final String id;
  final String symbol;
  final AssetMarket market;
  final AssetType type;
  final String currency;
  final String? nameEn;
  final String? nameCn;
  final AssetSearchHitSource source;
  final AssetSearchHitMatch match;

  /// Lower-is-better rank. Used to break ties within the same tier.
  /// Tier ordering is enforced by the search service before tie-breaks
  /// kick in — callers shouldn't reach across tiers using `rank` alone.
  final double rank;

  @override
  String toString() =>
      'AssetSearchHit($id, source=$source, match=$match, rank=$rank)';
}
