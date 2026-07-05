part of 'securities_search_service.dart';

mixin SecuritiesSearchOwnedMixin {
  AppDatabase get _db;

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
}
