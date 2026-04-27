import 'package:flutter_test/flutter_test.dart';

import 'package:naviwealth/core/db/migrations.dart';

import 'test_database.dart';

void main() {
  group('AppDatabase migrations', () {
    test('schemaVersion equals SchemaVersions.current', () {
      final db = makeTestDatabase();
      addTearDown(db.close);
      expect(db.schemaVersion, SchemaVersions.current);
    });

    test('onCreate enables foreign_keys via beforeOpen', () async {
      final db = makeTestDatabase();
      addTearDown(db.close);

      // Touch the DB so beforeOpen runs.
      await db.customSelect('SELECT 1').get();

      final pragma = await db.customSelect('PRAGMA foreign_keys;').getSingle();
      expect(pragma.data.values.first, 1);
    });

    test('schema includes all expected tables', () async {
      final db = makeTestDatabase();
      addTearDown(db.close);

      final tables = await db
          .customSelect(
            'SELECT name FROM sqlite_master '
            "WHERE type='table' AND name NOT LIKE 'sqlite_%' "
            'ORDER BY name',
          )
          .get();
      final names = tables.map((r) => r.read<String>('name')).toList();

      expect(
        names,
        containsAll(<String>[
          'accounts',
          'assets',
          'transactions',
          'fx_rates',
          'app_meta',
        ]),
      );
    });
  });
}
