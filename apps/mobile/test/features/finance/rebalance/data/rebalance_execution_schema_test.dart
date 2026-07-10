import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../../../core/persistence/test_database.dart';

void main() {
  test(
    'fresh database creates v36 local execution tables and indexes',
    () async {
      final db = makeTestDatabase();
      addTearDown(db.close);

      expect(db.schemaVersion, 36);
      final tables = await db.customSelect('''
      SELECT name FROM sqlite_master
      WHERE type = 'table' AND name LIKE 'rebalance_execution_%'
      ORDER BY name
    ''').get();
      expect(tables.map((row) => row.read<String>('name')), [
        'rebalance_execution_items',
        'rebalance_execution_sessions',
      ]);
      final indexes = await db.customSelect('''
      SELECT name FROM sqlite_master
      WHERE type = 'index' AND name LIKE 'idx_rebalance_execution_%'
    ''').get();
      expect(indexes.map((row) => row.read<String>('name')).toSet(), {
        'idx_rebalance_execution_one_active_owner',
        'idx_rebalance_execution_sessions_owner',
        'idx_rebalance_execution_applied_sequence',
        'idx_rebalance_execution_items_session',
        'idx_rebalance_execution_items_state',
      });
    },
  );

  test('v35 migration idempotently creates execution schema', () async {
    final dir = await Directory.systemTemp.createTemp('rebalance_v35_');
    addTearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });
    final file = File('${dir.path}/naviwealth.db');
    final legacy = sqlite3.open(file.path);
    try {
      legacy.execute('PRAGMA user_version = 35');
    } finally {
      legacy.close();
    }

    final db = AppDatabase(
      DatabaseConnection(NativeDatabase(file, logStatements: false)),
    );
    addTearDown(db.close);

    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.read<int>('user_version'), 36);
    final tables = await db.customSelect('''
      SELECT name FROM sqlite_master
      WHERE type = 'table' AND name IN (
        'rebalance_execution_sessions', 'rebalance_execution_items'
      )
    ''').get();
    expect(tables, hasLength(2));
  });

  test('schema enforces one active owner and unique applied order', () async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    const now = '2026-07-10T08:00:00.000Z';

    await db.customStatement('''
      INSERT INTO rebalance_execution_sessions
      (id, owner_user_id, status, plan_json, plan_fingerprint,
       created_at_iso, updated_at_iso, archived_at_iso)
      VALUES ('s1', 'owner-a', 'active', '{}', 'fp1', '$now', '$now', NULL)
    ''');
    await expectLater(
      db.customStatement('''
        INSERT INTO rebalance_execution_sessions
        (id, owner_user_id, status, plan_json, plan_fingerprint,
         created_at_iso, updated_at_iso, archived_at_iso)
        VALUES ('s2', 'owner-a', 'active', '{}', 'fp2', '$now', '$now', NULL)
      '''),
      throwsA(anything),
    );

    await db.customStatement('''
      INSERT INTO rebalance_execution_items
      (id, session_id, owner_user_id, position, suggestion_json, state,
       request_json, receipt_json, applied_sequence, created_at_iso, updated_at_iso)
      VALUES ('i1', 's1', 'owner-a', 0, '{}', 'applied', '{}', '{}', 1,
              '$now', '$now')
    ''');
    await expectLater(
      db.customStatement('''
        INSERT INTO rebalance_execution_items
        (id, session_id, owner_user_id, position, suggestion_json, state,
         request_json, receipt_json, applied_sequence, created_at_iso, updated_at_iso)
        VALUES ('i2', 's1', 'owner-a', 1, '{}', 'applied', '{}', '{}', 1,
                '$now', '$now')
      '''),
      throwsA(anything),
    );
  });
}
