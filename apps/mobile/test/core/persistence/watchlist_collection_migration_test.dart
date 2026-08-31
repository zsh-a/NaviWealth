import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

void main() {
  test(
    'v81 adds watchlist collections without rewriting existing items',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'naviwealth-watchlist-v82-',
      );
      addTearDown(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });
      final file = File('${dir.path}/naviwealth.db');
      final legacy = sqlite3.sqlite3.open(file.path);
      try {
        legacy.execute('''
        CREATE TABLE watchlist_items (
          owner_user_id TEXT NOT NULL,
          updated_at INTEGER NOT NULL,
          updated_by_device TEXT NOT NULL,
          hlc TEXT NOT NULL,
          deleted_at INTEGER,
          id TEXT PRIMARY KEY NOT NULL,
          symbol TEXT NOT NULL,
          market TEXT NOT NULL,
          added_at INTEGER NOT NULL,
          alert_rules_json TEXT NOT NULL DEFAULT '{}',
          UNIQUE(owner_user_id, market, symbol)
        )
      ''');
        legacy.execute('''
        INSERT INTO watchlist_items (
          owner_user_id, updated_at, updated_by_device, hlc, id, symbol,
          market, added_at, alert_rules_json
        ) VALUES (
          'u-test', 1, 'dev-test', '1:0:dev-test', 'us_stock:AAPL', 'AAPL',
          'us_stock', 1, '{}'
        )
      ''');
        legacy.execute('PRAGMA user_version = 81');
      } finally {
        legacy.close();
      }

      final db = AppDatabase(
        DatabaseConnection(NativeDatabase(file, logStatements: false)),
      );
      addTearDown(db.close);

      final itemCount = await db
          .customSelect('SELECT COUNT(*) AS count FROM watchlist_items')
          .getSingle();
      expect(itemCount.read<int>('count'), 1);

      for (final table in const [
        'watchlist_collections',
        'watchlist_collection_members',
      ]) {
        final columns = await db
            .customSelect('PRAGMA table_info($table)')
            .get();
        expect(columns, isNotEmpty, reason: table);
      }

      final version = await db.customSelect('PRAGMA user_version').getSingle();
      expect(version.read<int>('user_version'), 82);
    },
  );
}
