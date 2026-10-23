import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

void main() {
  for (final background in [false, true]) {
    for (final version in [1, 77, 97, 99]) {
      test(
        'rejects schema $version without modifying data (background=$background)',
        () async {
          final directory = await Directory.systemTemp.createTemp(
            'schema-baseline-',
          );
          addTearDown(() => directory.delete(recursive: true));
          final file = File('${directory.path}/lifeos.db');
          final raw = sqlite.sqlite3.open(file.path);
          raw.execute('CREATE TABLE retained_data (value TEXT NOT NULL)');
          raw.execute("INSERT INTO retained_data VALUES ('keep me')");
          raw.execute('PRAGMA user_version = $version');
          raw.close();

          for (var attempt = 0; attempt < 2; attempt++) {
            final db = AppDatabase(
              background
                  ? NativeDatabase.createInBackground(file)
                  : NativeDatabase(file),
            );
            try {
              await expectLater(
                db.ensureReady(),
                throwsA(
                  isA<UnsupportedDatabaseSchema>()
                      .having((e) => e.foundVersion, 'found version', version)
                      .having(
                        (e) => e.requiredVersion,
                        'required version',
                        db.schemaVersion,
                      ),
                ),
              );
            } finally {
              await db.close();
            }
            final check = sqlite.sqlite3.open(file.path);
            expect(
              check.select('PRAGMA user_version').single['user_version'],
              version,
            );
            expect(
              check.select('SELECT value FROM retained_data').single['value'],
              'keep me',
            );
            expect(
              check
                  .select("SELECT name FROM sqlite_master WHERE type = 'table'")
                  .map((r) => r['name']),
              ['retained_data'],
            );
            check.close();
          }
        },
      );
    }
  }

  test('current baseline reopens without losing data', () async {
    final directory = await Directory.systemTemp.createTemp('schema-reopen-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/lifeos.db');
    final initial = AppDatabase(NativeDatabase(file));
    await initial.customStatement('''
      INSERT INTO health_metrics (
        id, captured_at, kind, value, unit, owner_user_id,
        updated_at, updated_by_device, hlc
      ) VALUES (
        'metric', 1700000000, 'hrv_daily', 50, 'ms', 'owner',
        1700000000, 'device', '1700000000000.0000-device'
      )
    ''');
    await initial.close();
    final reopened = AppDatabase(NativeDatabase(file));
    addTearDown(reopened.close);
    expect(
      (await reopened.customSelect('PRAGMA user_version').getSingle())
          .read<int>('user_version'),
      reopened.schemaVersion,
    );
    expect(
      (await reopened
              .customSelect(
                "SELECT value FROM health_metrics WHERE id = 'metric'",
              )
              .getSingle())
          .read<double>('value'),
      50,
    );
  });
}
