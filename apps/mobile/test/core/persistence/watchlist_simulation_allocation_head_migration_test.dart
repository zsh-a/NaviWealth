import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

void main() {
  test(
    'v90 adds atomic allocation heads and preserves concurrent branches',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'naviwealth-watchlist-allocation-v91-',
      );
      addTearDown(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });
      final file = File('${dir.path}/naviwealth.db');
      final legacy = sqlite3.sqlite3.open(file.path);
      try {
        legacy.execute('''
        CREATE TABLE watchlist_simulation_allocation_versions (
          owner_user_id TEXT NOT NULL,
          updated_at INTEGER NOT NULL,
          updated_by_device TEXT NOT NULL,
          hlc TEXT NOT NULL,
          deleted_at INTEGER,
          id TEXT PRIMARY KEY NOT NULL,
          simulation_id TEXT NOT NULL,
          effective_at INTEGER NOT NULL,
          reason TEXT NOT NULL,
          cash_weight TEXT NOT NULL,
          is_complete INTEGER NOT NULL DEFAULT 0 CHECK (is_complete IN (0, 1)),
          created_at INTEGER NOT NULL,
          UNIQUE(owner_user_id, simulation_id, effective_at)
        )
      ''');
        legacy.execute('''
        INSERT INTO watchlist_simulation_allocation_versions VALUES (
          'u-test', 1700000000000, 'dev-a', '1700000000000.0000-dev-a', NULL,
          'allocation-a', 'simulation-1', 1700000000000, 'creation',
          '0.1', 1, 1700000000000
        )
      ''');
        legacy.execute('PRAGMA user_version = 90');
      } finally {
        legacy.close();
      }

      final db = AppDatabase(
        DatabaseConnection(NativeDatabase(file, logStatements: false)),
      );
      addTearDown(db.close);

      final columns = await db
          .customSelect(
            'PRAGMA table_info(watchlist_simulation_allocation_versions)',
          )
          .get();
      expect(
        columns.map((column) => column.read<String>('name')),
        containsAll([
          'previous_allocation_version_id',
          'requires_explicit_head',
        ]),
      );
      expect(
        await db
            .customSelect(
              'SELECT id FROM watchlist_simulation_allocation_versions',
            )
            .get()
            .then((rows) => rows.map((row) => row.read<String>('id')).toList()),
        ['allocation-a'],
      );

      await db.customStatement('''
      INSERT INTO watchlist_simulation_allocation_versions (
        owner_user_id, updated_at, updated_by_device, hlc, deleted_at,
        id, simulation_id, effective_at, reason,
        previous_allocation_version_id, requires_explicit_head,
        cash_weight, is_complete, created_at
      ) VALUES (
        'u-test', 1700000000001, 'dev-b', '1700000000001.0000-dev-b', NULL,
        'allocation-b', 'simulation-1', 1700000000000, 'reallocation',
        'allocation-a', 1, '0.2', 1, 1700000000001
      )
    ''');
      expect(
        await db
            .customSelect(
              'SELECT COUNT(*) AS count '
              'FROM watchlist_simulation_allocation_versions',
            )
            .getSingle()
            .then((row) => row.read<int>('count')),
        2,
      );

      final headColumns = await db
          .customSelect(
            'PRAGMA table_info(watchlist_simulation_allocation_heads)',
          )
          .get();
      expect(headColumns, isNotEmpty);
      await expectLater(
        db.customStatement('''
        INSERT INTO watchlist_simulation_allocation_heads (
          owner_user_id, updated_at, updated_by_device, hlc, deleted_at,
          id, simulation_id, allocation_version_id, created_at
        ) VALUES (
          'u-test', 1700000000001, 'dev-b', '1700000000001.0000-dev-b', NULL,
          'wrong-id', 'simulation-1', 'allocation-b', 1700000000001
        )
      '''),
        throwsA(isA<Exception>()),
      );

      final version = await db.customSelect('PRAGMA user_version').getSingle();
      expect(version.read<int>('user_version'), 91);
    },
  );
}
