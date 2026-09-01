import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

void main() {
  test('v89 adds nullable gross lifecycle columns', () async {
    final dir = await Directory.systemTemp.createTemp(
      'naviwealth-simulation-dividend-lifecycle-v89-',
    );
    addTearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });
    final file = File('${dir.path}/naviwealth.db');
    final legacy = sqlite3.sqlite3.open(file.path);
    try {
      legacy.execute('''
        CREATE TABLE watchlist_simulation_action_entries (
          id TEXT PRIMARY KEY NOT NULL,
          gross_amount TEXT,
          paper_state TEXT NOT NULL DEFAULT 'referenceOnly'
        )
      ''');
      legacy.execute('''
        INSERT INTO watchlist_simulation_action_entries
          (id, gross_amount, paper_state)
        VALUES ('action-1', '12.5', 'entitlementRecorded')
      ''');
      legacy.execute('PRAGMA user_version = 88');
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
        'receivable_gross_amount',
        'paper_cash_gross_amount',
        'state_at',
        'allocation_basis_key',
      ]),
    );
    final row = await db
        .customSelect(
          'SELECT * FROM watchlist_simulation_action_entries '
          "WHERE id = 'action-1'",
        )
        .getSingle();
    expect(row.read<String>('gross_amount'), '12.5');
    expect(row.read<String>('paper_state'), 'entitlementRecorded');
    expect(row.readNullable<String>('receivable_gross_amount'), isNull);
    expect(row.readNullable<String>('paper_cash_gross_amount'), isNull);
    expect(row.readNullable<int>('state_at'), isNull);

    final triggers = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'trigger' "
          "AND name LIKE 'trg_watchlist_sim_action_balances_%'",
        )
        .get();
    expect(triggers, hasLength(2));
    await expectLater(
      db.customStatement(
        'INSERT INTO watchlist_simulation_action_entries '
        '(id, gross_amount, paper_state, receivable_gross_amount, '
        'paper_cash_gross_amount) VALUES '
        "('invalid', '10', 'grossCashPendingTax', '10', '10')",
      ),
      throwsA(anything),
    );

    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.read<int>('user_version'), 91);
  });
}
