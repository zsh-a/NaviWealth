import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('v50 migration creates the typed knowledge relation schema', () async {
    final dir = await Directory.systemTemp.createTemp('knowledge_v50_');
    addTearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });
    final file = File('${dir.path}/naviwealth.db');
    final legacy = sqlite3.open(file.path);
    try {
      legacy.execute('PRAGMA user_version = 50');
    } finally {
      legacy.close();
    }

    final db = AppDatabase(
      DatabaseConnection(NativeDatabase(file, logStatements: false)),
    );
    addTearDown(db.close);

    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.read<int>('user_version'), 60);
    final table = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' "
          "AND name = 'knowledge_relations'",
        )
        .get();
    expect(table, hasLength(1));
    final indexes = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'index' "
          "AND name LIKE 'idx_knowledge_relations_%'",
        )
        .get();
    expect(indexes.map((row) => row.read<String>('name')).toSet(), {
      'idx_knowledge_relations_from',
      'idx_knowledge_relations_to',
    });
  });
}
