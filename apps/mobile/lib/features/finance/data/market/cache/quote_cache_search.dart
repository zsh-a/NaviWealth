part of 'quote_cache.dart';

Future<CachedSearch?> _readSearch(
  MarketCache cache,
  String query, {
  String? source,
}) async {
  final norm = query.trim().toLowerCase();
  if (norm.isEmpty) return null;
  final q = cache._db.select(cache._db.marketSymbolSearches)
    ..where((t) => t.query.equals(norm));
  if (source != null) q.where((t) => t.source.equals(source));
  q.orderBy([(t) => OrderingTerm.desc(t.fetchedAt)]);
  q.limit(1);
  final row = await q.getSingleOrNull();
  if (row == null) return null;
  final age = cache._clock.now().difference(row.fetchedAt);
  final freshness = _classify(
    age,
    fresh: cache._policy.searchFresh,
    stale: cache._policy.searchStaleWindow,
  );
  if (freshness == null) return null;
  final decoded = (jsonDecode(row.results) as List)
      .cast<Map<String, dynamic>>()
      .map(_symbolInfoFromJson)
      .toList(growable: false);
  return CachedSearch(
    results: decoded,
    fetchedAt: row.fetchedAt,
    freshness: freshness,
    source: row.source,
  );
}

Future<void> _writeSearch(
  MarketCache cache,
  String query,
  List<SymbolInfo> results, {
  required String source,
}) async {
  final norm = query.trim().toLowerCase();
  if (norm.isEmpty) return;
  final now = cache._clock.now();
  await cache._db
      .into(cache._db.marketSymbolSearches)
      .insertOnConflictUpdate(
        MarketSymbolSearchesCompanion.insert(
          query: norm,
          source: source,
          results: jsonEncode(
            results.map(_symbolInfoToJson).toList(growable: false),
          ),
          fetchedAt: now,
        ),
      );
}
