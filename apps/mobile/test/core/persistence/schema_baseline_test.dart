import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

void main() {
  for (final background in [false, true]) {
    test(
      'schema 100 preserves the legacy meal photo (background=$background)',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'schema-meal-views-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final file = File('${directory.path}/lifeos.db');
        final initial = AppDatabase(NativeDatabase(file));
        await initial.customStatement('''
        INSERT INTO health_meals (id, captured_at, day, meal_type, foods_json,
          owner_user_id, updated_at, updated_by_device, hlc)
        VALUES ('meal', 1700000000, 1700000000, 'lunch', '{"version":1,"foods":[]}',
          'owner', 1700000000, 'device', '1700000000000.0000-device')
      ''');
        await initial.close();
        final raw = sqlite.sqlite3.open(file.path);
        raw.execute('DROP TRIGGER trg_health_meal_deleted_photo');
        raw.execute('DROP TABLE health_meal_photos');
        raw.execute('''CREATE TABLE health_meal_photos (
        id TEXT NOT NULL PRIMARY KEY REFERENCES health_meals(id) ON DELETE CASCADE,
        owner_user_id TEXT NOT NULL, bytes BLOB NOT NULL)''');
        raw.execute(
          "INSERT INTO health_meal_photos VALUES ('meal', 'owner', X'010203')",
        );
        raw.execute('PRAGMA user_version = 100');
        raw.close();
        final upgraded = AppDatabase(
          background
              ? NativeDatabase.createInBackground(file)
              : NativeDatabase(file),
        );
        await upgraded.ensureReady();
        final photo =
            (await upgraded.select(upgraded.healthMealPhotos).get()).single;
        expect(photo.mealId, 'meal');
        expect(photo.id, 'meal');
        expect(photo.bytes, [1, 2, 3]);
        expect(photo.viewRole, 'overview');
        expect(photo.position, 0);
        await upgraded.customStatement(
          "UPDATE health_meals SET deleted_at = 1700000001 WHERE id = 'meal'",
        );
        expect(await upgraded.select(upgraded.healthMealPhotos).get(), isEmpty);
        await upgraded.close();
        final reopened = AppDatabase(NativeDatabase(file));
        await reopened.ensureReady();
        expect(
          (await reopened.select(reopened.healthMeals).get()).single.deletedAt,
          isNotNull,
        );
        await reopened.close();
      },
    );
  }

  for (final background in [false, true]) {
    for (final version in [1, 77, 98, 102]) {
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

  for (final background in [false, true]) {
    test(
      'schema 99 adds meals without resetting existing data (background=$background)',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'schema-meals-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final file = File('${directory.path}/lifeos.db');
        final initial = AppDatabase(NativeDatabase(file));
        await initial.customStatement('''
        INSERT INTO health_metrics (id, captured_at, kind, value, unit,
          owner_user_id, updated_at, updated_by_device, hlc)
        VALUES ('existing-weight', 1700000000, 'weight', 70, 'kg',
          'owner', 1700000000, 'device', '1700000000000.0000-device')
      ''');
        await initial.close();
        // These are the only schema additions since 99. Removing them produces
        // the previous baseline's schema while keeping all existing row data.
        final raw = sqlite.sqlite3.open(file.path);
        raw.execute('DROP TABLE health_meal_photos');
        raw.execute('DROP TABLE health_meals');
        raw.execute('PRAGMA user_version = 99');
        raw.close();
        final upgraded = AppDatabase(
          background
              ? NativeDatabase.createInBackground(file)
              : NativeDatabase(file),
        );
        await upgraded.ensureReady();
        expect(
          (await upgraded
                  .customSelect(
                    "SELECT value FROM health_metrics WHERE id = 'existing-weight'",
                  )
                  .getSingle())
              .read<double>('value'),
          70,
        );
        expect(await upgraded.select(upgraded.healthMeals).get(), isEmpty);
        expect(await upgraded.select(upgraded.healthMealPhotos).get(), isEmpty);
        expect(
          (await upgraded.customSelect('PRAGMA user_version').getSingle())
              .read<int>('user_version'),
          101,
        );
        await upgraded.close();
        final reopened = AppDatabase(NativeDatabase(file));
        await reopened.ensureReady();
        expect(
          (await reopened.select(reopened.healthMetrics).get()).single.id,
          'existing-weight',
        );
        await reopened.close();
      },
    );
  }
}
