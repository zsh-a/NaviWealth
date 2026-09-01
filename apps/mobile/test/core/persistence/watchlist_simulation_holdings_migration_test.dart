import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

void main() {
  test('v88 preserves legacy mode and adds holding version tables', () async {
    final dir = await Directory.systemTemp.createTemp(
      'naviwealth-simulation-holdings-v88-',
    );
    addTearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });
    final file = File('${dir.path}/naviwealth.db');
    final legacy = sqlite3.sqlite3.open(file.path);
    try {
      legacy.execute('''
        CREATE TABLE watchlist_simulations (
          owner_user_id TEXT NOT NULL,
          updated_at INTEGER NOT NULL,
          updated_by_device TEXT NOT NULL,
          hlc TEXT NOT NULL,
          deleted_at INTEGER,
          id TEXT PRIMARY KEY NOT NULL,
          collection_id TEXT NOT NULL,
          name TEXT NOT NULL,
          base_currency TEXT NOT NULL,
          starting_capital TEXT NOT NULL,
          cash_weight TEXT NOT NULL DEFAULT '0',
          baseline_at INTEGER NOT NULL,
          created_at INTEGER NOT NULL
        )
      ''');
      legacy.execute('''
        INSERT INTO watchlist_simulations VALUES (
          'u-test', 1700000000, 'dev-test', '1700000000:0:dev-test', NULL,
          'simulation-legacy', 'collection-1', 'Legacy', 'USD', '1000', '0',
          1700000000, 1700000000
        )
      ''');
      legacy.execute('PRAGMA user_version = 87');
    } finally {
      legacy.close();
    }

    final db = AppDatabase(
      DatabaseConnection(NativeDatabase(file, logStatements: false)),
    );
    addTearDown(db.close);

    final legacyRow = await db
        .customSelect(
          'SELECT calculation_mode FROM watchlist_simulations '
          "WHERE id = 'simulation-legacy'",
        )
        .getSingle();
    expect(legacyRow.read<String>('calculation_mode'), 'weightedDailyChangeV1');

    for (final table in const [
      'watchlist_simulation_allocation_versions',
      'watchlist_simulation_holding_versions',
    ]) {
      final columns = await db.customSelect('PRAGMA table_info($table)').get();
      final names = columns.map((row) => row.read<String>('name')).toSet();
      expect(
        names,
        containsAll(['id', 'owner_user_id', 'hlc', 'deleted_at']),
        reason: table,
      );
    }
    final holdingColumns = await db
        .customSelect(
          'PRAGMA table_info(watchlist_simulation_holding_versions)',
        )
        .get();
    expect(
      holdingColumns.map((row) => row.read<String>('name')),
      containsAll([
        'allocation_version_id',
        'simulation_id',
        'watchlist_item_id',
        'quantity',
        'raw_price',
        'price_currency',
        'price_as_of',
        'price_source',
        'fx_to_base',
        'effective_at',
      ]),
    );

    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.read<int>('user_version'), 89);
  });
}
