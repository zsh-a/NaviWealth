part of 'securities_search_service.dart';

mixin SecuritiesSearchCatalogMixin {
  AppDatabase get _db;

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
      '$escaped%',
      '$escaped%',
      '$escaped%',
      '$escaped%',
      '$escaped%',
      // exclude rows that already matched in tier 2
      lower,
      lower,
      lower,
      lower,
      lower,
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
