import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

void main() {
  test('v87 adds synced paper-only simulation action entries', () async {
    final dir = await Directory.systemTemp.createTemp(
      'naviwealth-simulation-actions-v87-',
    );
    addTearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });
    final file = File('${dir.path}/naviwealth.db');
    final legacy = sqlite3.sqlite3.open(file.path);
    try {
      legacy.execute('PRAGMA user_version = 86');
    } finally {
      legacy.close();
    }

    final db = AppDatabase(
      DatabaseConnection(NativeDatabase(file, logStatements: false)),
    );
    addTearDown(db.close);

    final columns = await db
        .customSelect('PRAGMA table_info(watchlist_simulation_action_entries)')
        .get();
    final names = columns.map((row) => row.read<String>('name')).toSet();
    expect(
      names,
      containsAll([
        'id',
        'owner_user_id',
        'hlc',
        'deleted_at',
        'simulation_id',
        'watchlist_item_id',
        'source',
        'dataset',
        'source_key',
        'revision_hash',
        'record_date',
        'ex_date',
        'pay_date',
        'currency',
        'cash_per_share',
        'eligible_quantity',
        'gross_amount',
        'withholding_tax_amount',
        'net_amount',
        'base_currency_amount',
      ]),
    );

    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.read<int>('user_version'), 88);
  });
}
