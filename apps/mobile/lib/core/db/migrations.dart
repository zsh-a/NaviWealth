import 'package:drift/drift.dart';

import 'app_database.dart';

/// Schema versions tracked by the app.
///
/// Bump on every schema change and add a corresponding step below. Never
/// renumber — version numbers are recorded in user databases.
class SchemaVersions {
  static const int v1Initial = 1;

  /// FIR-26: market_quotes / market_history_bars / market_symbol_searches.
  static const int v2MarketCache = 2;

  static const int current = v2MarketCache;
}

MigrationStrategy buildMigrationStrategy(AppDatabase db) {
  return MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
    },
    onUpgrade: (m, from, to) async {
      for (var v = from + 1; v <= to; v++) {
        switch (v) {
          case SchemaVersions.v2MarketCache:
            await m.createTable(db.marketQuotes);
            await m.createTable(db.marketHistoryBars);
            await m.createTable(db.marketSymbolSearches);
          default:
            throw StateError(
              'No migration registered for schema upgrade to v$v.',
            );
        }
      }
    },
    beforeOpen: (details) async {
      // Foreign keys must be enabled per-connection — they are off by
      // default in SQLite/SQLCipher and the setting does not persist.
      await db.customStatement('PRAGMA foreign_keys = ON;');
    },
  );
}
