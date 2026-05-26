import 'package:drift/drift.dart' hide Column;

import '../../core/persistence/app_database.dart';
import '../../domain/values/asset_market.dart';
import '../domain/enums.dart';
import 'asset_search_hit.dart';

/// Strict, four-tier offline search over the local securities universe.
///
/// FIR-76: a fresh install with **zero** recorded trades must still find
/// the user's instrument by symbol, English name, Chinese name, full
/// pinyin or pinyin initials — and must do so without making a single
/// HTTP request. The trade-entry form calls into this service first;
/// the network-backed [MarketDataService] is only invoked when the
/// caller explicitly requests an enrichment (FIR-78).
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
class SecuritiesSearchService {
  SecuritiesSearchService({required AppDatabase db}) : _db = db;

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

  // ---------- Tier 1: owned ----------

  Future<List<AssetSearchHit>> _searchOwned(
    String query,
    String? marketWire,
    int limit,
  ) async {
    final lower = query.toLowerCase();
    final cjk = _isCjk(query);

    // The owned set is small (the average user has < 50 instruments),
    // so a single LIKE-OR pass with rank assigned in Dart is simpler
    // and faster than three separate roundtrips. We pull a generous
    // candidate window (`limit * 4`) to give the in-memory ranker
    // headroom; everything outside that window can't possibly outrank
    // an exact match anyway.
    final escaped = _escapeLike(lower);
    final cjkEscaped = _escapeLike(query);
    final args = <Object?>[
      escaped,
      '$escaped%',
      '%$escaped%',
      escaped,
      '$escaped%',
      '%$escaped%',
      if (cjk) '%$cjkEscaped%',
      ?marketWire,
      limit * 4,
    ];

    final marketClause = marketWire == null ? '' : 'AND market = ? ';
    final cjkClause = cjk ? 'OR name LIKE ? ESCAPE \'\\\' ' : '';

    final rows = await _db.customSelect('''
      SELECT id, symbol, market, type, currency, name
      FROM assets
      WHERE deleted_at IS NULL
        AND market IS NOT NULL
        AND (
          LOWER(symbol) = ?
          OR LOWER(symbol) LIKE ? ESCAPE '\\'
          OR LOWER(symbol) LIKE ? ESCAPE '\\'
          OR LOWER(name) = ?
          OR LOWER(name) LIKE ? ESCAPE '\\'
          OR LOWER(name) LIKE ? ESCAPE '\\'
          $cjkClause
        )
        $marketClause
      LIMIT ?
      ''', variables: _vars(args)).get();

    final hits = <AssetSearchHit>[];
    for (final row in rows) {
      final symbol = row.read<String>('symbol');
      final wire = row.read<String?>('market');
      final assetMarket = wire == null
          ? AssetMarket.unknown
          : assetMarketFromWire(wire) ?? AssetMarket.unknown;
      final typeName = row.read<String>('type');
      final type = AssetType.values.byName(typeName);
      final name = row.read<String?>('name');

      // Stable per-row priority: 0 = exact, 1 = prefix, 2 = substring.
      final symLower = symbol.toLowerCase();
      final nameLower = (name ?? '').toLowerCase();
      double rank;
      AssetSearchHitMatch match;
      if (symLower == lower || nameLower == lower) {
        rank = 0;
        match = AssetSearchHitMatch.exact;
      } else if (symLower.startsWith(lower) || nameLower.startsWith(lower)) {
        rank = 1;
        match = AssetSearchHitMatch.prefix;
      } else if (cjk && (name ?? '').contains(query)) {
        rank = 2;
        match = AssetSearchHitMatch.cjkSubstring;
      } else {
        rank = 3;
        match = AssetSearchHitMatch.fts;
      }

      hits.add(
        AssetSearchHit(
          id: row.read<String>('id'),
          symbol: symbol,
          market: assetMarket,
          type: type,
          currency: row.read<String>('currency'),
          nameEn: name,
          nameCn: null,
          source: AssetSearchHitSource.owned,
          match: match,
          rank: rank,
        ),
      );
    }
    return hits;
  }

  Iterable<AssetSearchHit> _sortOwned(List<AssetSearchHit> hits) {
    final sorted = [...hits]
      ..sort((a, b) {
        final r = a.rank.compareTo(b.rank);
        if (r != 0) return r;
        return a.symbol.compareTo(b.symbol);
      });
    return sorted;
  }

  // ---------- Tiers 2-4: catalog ----------

  Future<List<AssetSearchHit>> _searchCatalog(
    String query,
    String? marketWire,
    Set<_MarketSymbolKey> ownedKeys,
    int budget,
  ) async {
    final lower = query.toLowerCase();
    final cjk = _isCjk(query);

    // Tier 2 & 3 in one query: a UNION ALL where the rank column
    // marks the tier. This collapses three potential round-trips into
    // one and lets SQLite's planner skip a tier entirely once the
    // exact-match index hits enough rows.
    final escaped = _escapeLike(lower);
    final ftsToken = _ftsTokenFor(query);

    final pickedKeys = <_MarketSymbolKey>{};
    final hits = <AssetSearchHit>[];

    // ---- Tier 2: exact ----
    final exactArgs = <Object?>[
      lower,
      lower,
      lower,
      lower,
      lower,
      ?marketWire,
      budget,
    ];
    final exactRows = await _db.customSelect('''
      SELECT id, symbol, market, type, currency, name_en, name_cn,
             pinyin, pinyin_initials
      FROM securities_catalog
      WHERE (
        LOWER(symbol) = ?
        OR LOWER(name_en) = ?
        OR LOWER(name_cn) = ?
        OR LOWER(pinyin) = ?
        OR LOWER(pinyin_initials) = ?
      )
      ${marketWire == null ? '' : 'AND market = ?'}
      ORDER BY symbol
      LIMIT ?
      ''', variables: _vars(exactArgs)).get();
    for (final row in exactRows) {
      _accumulate(
        row,
        AssetSearchHitMatch.exact,
        rank: 0,
        ownedKeys: ownedKeys,
        pickedKeys: pickedKeys,
        hits: hits,
      );
      if (hits.length >= budget) return hits;
    }

    // ---- Tier 3: prefix ----
    final prefixArgs = <Object?>[
      '$escaped%', '$escaped%', '$escaped%', '$escaped%', '$escaped%',
      // exclude rows that already matched in tier 2
      lower, lower, lower, lower, lower,
      ?marketWire,
      budget * 4,
    ];
    final prefixRows = await _db.customSelect('''
      SELECT id, symbol, market, type, currency, name_en, name_cn,
             pinyin, pinyin_initials
      FROM securities_catalog
      WHERE (
        LOWER(symbol) LIKE ? ESCAPE '\\'
        OR LOWER(name_en) LIKE ? ESCAPE '\\'
        OR LOWER(name_cn) LIKE ? ESCAPE '\\'
        OR LOWER(pinyin) LIKE ? ESCAPE '\\'
        OR LOWER(pinyin_initials) LIKE ? ESCAPE '\\'
      )
      AND NOT (
        LOWER(symbol) = ?
        OR LOWER(name_en) = ?
        OR LOWER(name_cn) = ?
        OR LOWER(pinyin) = ?
        OR LOWER(pinyin_initials) = ?
      )
      ${marketWire == null ? '' : 'AND market = ?'}
      ORDER BY symbol
      LIMIT ?
      ''', variables: _vars(prefixArgs)).get();
    for (final row in prefixRows) {
      _accumulate(
        row,
        AssetSearchHitMatch.prefix,
        rank: 1,
        ownedKeys: ownedKeys,
        pickedKeys: pickedKeys,
        hits: hits,
      );
      if (hits.length >= budget) return hits;
    }

    // ---- Tier 4: FTS5 ----
    if (ftsToken.isNotEmpty) {
      final ftsArgs = <Object?>[ftsToken, ?marketWire, budget * 4];
      final ftsRows = await _db.customSelect('''
        SELECT c.id, c.symbol, c.market, c.type, c.currency,
               c.name_en, c.name_cn, c.pinyin, c.pinyin_initials,
               bm25(securities_catalog_fts) AS fts_rank
        FROM securities_catalog_fts AS f
        JOIN securities_catalog AS c ON c.rowid = f.rowid
        WHERE securities_catalog_fts MATCH ?
        ${marketWire == null ? '' : 'AND c.market = ?'}
        ORDER BY fts_rank
        LIMIT ?
        ''', variables: _vars(ftsArgs)).get();
      for (final row in ftsRows) {
        final ftsRank = row.read<double?>('fts_rank') ?? 999;
        _accumulate(
          row,
          AssetSearchHitMatch.fts,
          rank: 2 + ftsRank,
          ownedKeys: ownedKeys,
          pickedKeys: pickedKeys,
          hits: hits,
        );
        if (hits.length >= budget) return hits;
      }
    }

    // ---- Tier 4b: CJK substring fallback ----
    //
    // unicode61 treats `贵州茅台` as a single token, so the FTS path
    // misses queries that are a substring of a Chinese name unless the
    // exact substring already lives in `aliases`. We backstop with a
    // plain `LIKE '%query%'` against `name_cn` so user searches like
    // `茅台` still surface `贵州茅台` even when the bundle skipped the
    // alias.
    if (cjk && hits.length < budget) {
      final cjkEscaped = _escapeLike(query);
      final cjkArgs = <Object?>['%$cjkEscaped%', ?marketWire, budget * 4];
      final cjkRows = await _db.customSelect('''
        SELECT id, symbol, market, type, currency,
               name_en, name_cn, pinyin, pinyin_initials
        FROM securities_catalog
        WHERE name_cn LIKE ? ESCAPE '\\'
        ${marketWire == null ? '' : 'AND market = ?'}
        ORDER BY symbol
        LIMIT ?
        ''', variables: _vars(cjkArgs)).get();
      for (final row in cjkRows) {
        _accumulate(
          row,
          AssetSearchHitMatch.cjkSubstring,
          rank: 3,
          ownedKeys: ownedKeys,
          pickedKeys: pickedKeys,
          hits: hits,
        );
        if (hits.length >= budget) return hits;
      }
    }

    return hits;
  }

  void _accumulate(
    QueryRow row,
    AssetSearchHitMatch match, {
    required double rank,
    required Set<_MarketSymbolKey> ownedKeys,
    required Set<_MarketSymbolKey> pickedKeys,
    required List<AssetSearchHit> hits,
  }) {
    final symbol = row.read<String>('symbol');
    final wire = row.read<String>('market');
    final assetMarket = assetMarketFromWire(wire) ?? AssetMarket.unknown;
    final key = _MarketSymbolKey(wire, symbol.toLowerCase());
    if (ownedKeys.contains(key) || !pickedKeys.add(key)) return;

    final typeName = row.read<String>('type');
    final type = AssetType.values.byName(typeName);
    hits.add(
      AssetSearchHit(
        id: row.read<String>('id'),
        symbol: symbol,
        market: assetMarket,
        type: type,
        currency: row.read<String>('currency'),
        nameEn: row.read<String?>('name_en'),
        nameCn: row.read<String?>('name_cn'),
        source: AssetSearchHitSource.catalog,
        match: match,
        rank: rank,
      ),
    );
  }

  /// Builds an FTS5 query token. We append `*` for prefix expansion so
  /// `aap` matches `AAPL`, and quote the token to disarm operators a
  /// user might type into the picker (`"foo bar" OR baz`). Returns an
  /// empty string when the input has no tokenizable characters — the
  /// caller skips the FTS round-trip in that case to avoid sending an
  /// empty MATCH expression (which sqlite raises on).
  String _ftsTokenFor(String query) {
    final cleaned = query
        .replaceAll(RegExp(r'["\(\)*]'), ' ')
        .trim()
        .toLowerCase();
    if (cleaned.isEmpty) return '';
    // Compose `"<token>" *` for each space-separated word so each acts
    // as a prefix. `unicode61 remove_diacritics 2` lower-cases and
    // tokenizes naturally; quoting protects against accidental
    // operators inside the query.
    return cleaned
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .map((t) => '"$t"*')
        .join(' ');
  }
}

class _MarketSymbolKey {
  const _MarketSymbolKey(this.market, this.symbolLower);

  final String market;
  final String symbolLower;

  @override
  bool operator ==(Object other) =>
      other is _MarketSymbolKey &&
      other.market == market &&
      other.symbolLower == symbolLower;

  @override
  int get hashCode => Object.hash(market, symbolLower);
}

/// Heuristic: does the query contain CJK characters? A character in the
/// CJK Unified Ideographs block (U+4E00–U+9FFF) is enough — we don't
/// need a full Unicode property table for the substring fallback.
bool _isCjk(String s) {
  for (final rune in s.runes) {
    if (rune >= 0x4E00 && rune <= 0x9FFF) return true;
  }
  return false;
}

/// Escape `%` and `_` (and the escape char itself) so a user query that
/// happens to contain `%foo%` doesn't widen the LIKE to a full table
/// scan. Pairs with the `ESCAPE '\\'` clause on each LIKE.
String _escapeLike(String s) {
  return s
      .replaceAll(r'\', r'\\')
      .replaceAll('%', r'\%')
      .replaceAll('_', r'\_');
}

/// Build a `List<Variable<Object>>` from a list of dart values for a
/// `customSelect` call. Drift exposes `Variable.withInt` /
/// `Variable.withString` etc. but no generic factory; this helper picks
/// the right typed factory per element so callers can stay readable.
List<Variable<Object>> _vars(List<Object?> args) {
  final out = <Variable<Object>>[];
  for (final v in args) {
    if (v == null) {
      // customSelect placeholders can't represent NULL — callers gate
      // null args with `if (...)` upstream, so reaching this branch is
      // a programming error worth surfacing rather than silently
      // dropping the param and shifting every later placeholder.
      throw ArgumentError('null variable in catalog search args');
    }
    if (v is int) {
      out.add(Variable.withInt(v));
    } else if (v is String) {
      out.add(Variable.withString(v));
    } else if (v is double) {
      out.add(Variable.withReal(v));
    } else if (v is bool) {
      out.add(Variable.withBool(v));
    } else {
      throw ArgumentError(
        'unsupported variable type ${v.runtimeType} in catalog search args',
      );
    }
  }
  return out;
}
