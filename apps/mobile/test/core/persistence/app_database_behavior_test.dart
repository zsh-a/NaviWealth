import 'dart:typed_data';

import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'test_database.dart';

void main() {
  test('opens with SQLite foreign keys enabled', () async {
    final db = makeTestDatabase();
    addTearDown(db.close);

    final pragma = await db.customSelect('PRAGMA foreign_keys').getSingle();
    expect(pragma.read<int>('foreign_keys'), 1);
  });

  test('memory_embeddings rejects missing memory rows', () async {
    final db = makeTestDatabase();
    addTearDown(db.close);

    await expectLater(
      db.customStatement(
        '''
        INSERT INTO memory_embeddings (
          memory_id,
          fingerprint,
          dimension,
          vector_bytes
        ) VALUES (?, ?, ?, ?)
        ''',
        [
          'missing',
          'stub-v1',
          2,
          Uint8List.fromList([0, 0, 0, 0]),
        ],
      ),
      throwsA(isA<SqliteException>()),
    );
  });

  test('deleting a memory cascades to its embedding vector', () async {
    final db = makeTestDatabase();
    addTearDown(db.close);

    await db.customStatement(
      '''
      INSERT INTO memories (
        id,
        kind,
        scope,
        owner_user_id,
        title,
        summary,
        payload_json,
        entities_json,
        created_at,
        updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        'mem-1',
        'semantic',
        '*',
        'user-1',
        'Preference',
        'User prefers concise answers.',
        '{}',
        '[]',
        1,
        1,
      ],
    );
    await db.customStatement(
      '''
      INSERT INTO memory_embeddings (
        memory_id,
        fingerprint,
        dimension,
        vector_bytes
      ) VALUES (?, ?, ?, ?)
      ''',
      [
        'mem-1',
        'stub-v1',
        2,
        Uint8List.fromList([0, 0, 0, 0]),
      ],
    );

    await db.customStatement('DELETE FROM memories WHERE id = ?', ['mem-1']);

    final rows = await db
        .customSelect('SELECT memory_id FROM memory_embeddings')
        .get();
    expect(rows, isEmpty);
  });
}
