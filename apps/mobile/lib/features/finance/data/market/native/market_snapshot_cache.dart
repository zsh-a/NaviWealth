import 'package:naviwealth/core/persistence/app_database.dart';

/// FinanceOS owns persistence; the embedded Rust engine uses NoCache.
class MarketSnapshotCache {
  MarketSnapshotCache(this.db);
  final AppDatabase db;

  Future<String?> read(String key) async {
    final row = await (db.select(
      db.marketDataSnapshots,
    )..where((t) => t.requestKey.equals(key))).getSingleOrNull();
    return row?.envelope;
  }

  Future<void> write(String key, String envelope, DateTime fetchedAt) async {
    await db.transaction(() async {
      await db
          .into(db.marketDataSnapshots)
          .insertOnConflictUpdate(
            MarketDataSnapshotsCompanion.insert(
              requestKey: key,
              envelope: envelope,
              fetchedAt: fetchedAt,
            ),
          );
      // Exact windows retain their provenance; bound growth as windows slide.
      await db.customStatement('''
        DELETE FROM market_data_snapshots WHERE request_key NOT IN (
          SELECT request_key FROM market_data_snapshots
          ORDER BY fetched_at DESC, request_key LIMIT 256
        )
      ''');
    });
  }
}
