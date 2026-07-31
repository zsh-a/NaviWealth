import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../../../core/persistence/test_database.dart';

void main() {
  test('fresh database creates local execution tables and indexes', () async {
    final db = makeTestDatabase();
    addTearDown(db.close);

    expect(db.schemaVersion, 70);
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
    final columns = await db
        .customSelect('PRAGMA table_info(rebalance_execution_items)')
        .get();
    expect(
      columns.map((row) => row.read<String>('name')),
      contains('failure_code'),
    );
  });

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
    expect(version.read<int>('user_version'), db.schemaVersion);
    final tables = await db.customSelect('''
      SELECT name FROM sqlite_master
      WHERE type = 'table' AND name IN (
        'rebalance_execution_sessions', 'rebalance_execution_items'
      )
    ''').get();
    expect(tables, hasLength(2));
  });

  test(
    'v36 migration classifies legacy failures and clears stale errors',
    () async {
      final dir = await Directory.systemTemp.createTemp('rebalance_v36_');
      addTearDown(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });
      final file = File('${dir.path}/naviwealth.db');
      final legacy = sqlite3.open(file.path);
      try {
        legacy.execute('PRAGMA user_version = 36');
        legacy.execute('''
        CREATE TABLE rebalance_execution_sessions (
          id TEXT PRIMARY KEY, owner_user_id TEXT NOT NULL, status TEXT NOT NULL,
          plan_json TEXT NOT NULL, plan_fingerprint TEXT NOT NULL,
          created_at_iso TEXT NOT NULL, updated_at_iso TEXT NOT NULL,
          archived_at_iso TEXT, UNIQUE (id, owner_user_id)
        )
      ''');
        legacy.execute('''
        CREATE TABLE rebalance_execution_items (
          id TEXT PRIMARY KEY, session_id TEXT NOT NULL, owner_user_id TEXT NOT NULL,
          position INTEGER NOT NULL, suggestion_json TEXT NOT NULL,
          request_json TEXT, receipt_json TEXT, state TEXT NOT NULL, error TEXT,
          attempt_token TEXT, lease_until_iso TEXT, applied_sequence INTEGER,
          recovery_was_applied INTEGER NOT NULL DEFAULT 0,
          created_at_iso TEXT NOT NULL, updated_at_iso TEXT NOT NULL,
          UNIQUE (session_id, position)
        )
      ''');
        for (final row in const <(String, String)>[
          ('apply', 'applyFailed'),
          ('undo', 'undoFailed'),
          ('recovery', 'recoveryBlocked'),
          ('ready', 'ready'),
        ]) {
          legacy.execute(
            'INSERT INTO rebalance_execution_items '
            '(id, session_id, owner_user_id, position, suggestion_json, state, '
            ' error, created_at_iso, updated_at_iso) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
            [
              row.$1,
              'session',
              'owner',
              row.$1.hashCode,
              '{}',
              row.$2,
              row.$1 == 'apply'
                  ? List<String>.filled(600, 'x').join()
                  : 'legacy debug',
              '2026-07-10T08:00:00.000Z',
              '2026-07-10T08:00:00.000Z',
            ],
          );
        }
      } finally {
        legacy.close();
      }

      final db = AppDatabase(
        DatabaseConnection(NativeDatabase(file, logStatements: false)),
      );
      addTearDown(db.close);

      final rows = await db
          .customSelect(
            'SELECT id, failure_code, error FROM rebalance_execution_items ORDER BY id',
          )
          .get();
      expect(
        {
          for (final row in rows)
            row.read<String>('id'): (
              row.read<String?>('failure_code'),
              row.read<String?>('error'),
            ),
        },
        {
          'apply': ('legacyApplyFailure', List<String>.filled(512, 'x').join()),
          'ready': (null, null),
          'recovery': ('recoveryCorrupt', 'legacy debug'),
          'undo': ('legacyUndoFailure', 'legacy debug'),
        },
      );
      await expectLater(
        db.customStatement(
          "UPDATE rebalance_execution_items SET state = 'applyFailed', "
          "request_json = '{}', failure_code = NULL WHERE id = 'ready'",
        ),
        throwsA(anything),
      );
      await expectLater(
        db.customStatement(
          "UPDATE rebalance_execution_items SET failure_code = 'internal', "
          "error = 'debug' WHERE id = 'ready'",
        ),
        throwsA(anything),
      );
    },
  );

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
        INSERT INTO rebalance_execution_items
        (id, session_id, owner_user_id, position, suggestion_json, state,
         request_json, created_at_iso, updated_at_iso)
        VALUES ('missing-code', 's1', 'owner-a', 2, '{}', 'applyFailed',
                '{}', '$now', '$now')
      '''),
      throwsA(anything),
    );
    await expectLater(
      db.customStatement('''
        INSERT INTO rebalance_execution_items
        (id, session_id, owner_user_id, position, suggestion_json, state,
         request_json, failure_code, error, created_at_iso, updated_at_iso)
        VALUES ('stale-issue', 's1', 'owner-a', 3, '{}', 'ready',
                '{}', 'internal', 'debug', '$now', '$now')
      '''),
      throwsA(anything),
    );
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
