import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

void main() {
  test('v83 adds paper-only watchlist simulation tables', () async {
    final dir = await Directory.systemTemp.createTemp(
      'naviwealth-watchlist-simulation-v84-',
    );
    addTearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });
    final file = File('${dir.path}/naviwealth.db');
    final legacy = sqlite3.sqlite3.open(file.path);
    try {
      legacy.execute('PRAGMA user_version = 83');
    } finally {
      legacy.close();
    }

    final db = AppDatabase(
      DatabaseConnection(NativeDatabase(file, logStatements: false)),
    );
    addTearDown(db.close);

    final simulations = await db
        .customSelect('PRAGMA table_info(watchlist_simulations)')
        .get();
    expect(
      simulations.map((row) => row.read<String>('name')),
      containsAll([
        'collection_id',
        'starting_capital',
        'cash_weight',
        'baseline_at',
        'owner_user_id',
        'hlc',
      ]),
    );
    final positions = await db
        .customSelect('PRAGMA table_info(watchlist_simulation_positions)')
        .get();
    expect(
      positions.map((row) => row.read<String>('name')),
      containsAll([
        'simulation_id',
        'watchlist_item_id',
        'target_weight',
        'owner_user_id',
        'hlc',
      ]),
    );

    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.read<int>('user_version'), 84);
  });
}
