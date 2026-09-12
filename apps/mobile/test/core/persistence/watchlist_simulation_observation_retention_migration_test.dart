import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

/// v92 removes the v90 tombstone triggers that purged device-local
/// `watchlist_simulation_observations` rows on every soft delete.
///
/// The delete of a paper simulation is undoable, so an upgraded install must
/// keep the observed curve across the tombstone — otherwise the undo offered
/// in the UI would restore the scenario with its history silently reset to the
/// baseline. Rows are still cleaned up when the definition row is really
/// removed, which is what the surviving `AFTER DELETE` trigger covers.
void main() {
  test(
    'v91 -> v92 keeps observations across a tombstone and still cleans up '
    'on a real removal',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'naviwealth-watchlist-observation-v92-',
      );
      addTearDown(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });
      final file = File('${dir.path}/naviwealth.db');
      final legacy = sqlite3.sqlite3.open(file.path);
      try {
        legacy.execute('''
        CREATE TABLE watchlist_simulations (
          id TEXT PRIMARY KEY NOT NULL,
          owner_user_id TEXT NOT NULL,
          deleted_at INTEGER
        )
      ''');
        legacy.execute('''
        CREATE TABLE watchlist_simulation_observations (
          id TEXT PRIMARY KEY NOT NULL,
          owner_user_id TEXT NOT NULL,
          simulation_id TEXT NOT NULL
        )
      ''');
        legacy.execute('''
        CREATE TRIGGER trg_watchlist_simulation_tombstone_insert
        AFTER INSERT ON watchlist_simulations
        WHEN NEW.deleted_at IS NOT NULL
        BEGIN
          DELETE FROM watchlist_simulation_observations
          WHERE owner_user_id = NEW.owner_user_id
            AND simulation_id = NEW.id;
        END
      ''');
        legacy.execute('''
        CREATE TRIGGER trg_watchlist_simulation_tombstone_cleanup
        AFTER UPDATE OF deleted_at ON watchlist_simulations
        WHEN NEW.deleted_at IS NOT NULL
        BEGIN
          DELETE FROM watchlist_simulation_observations
          WHERE owner_user_id = NEW.owner_user_id
            AND simulation_id = NEW.id;
        END
      ''');
        legacy.execute('''
        INSERT INTO watchlist_simulations (id, owner_user_id, deleted_at)
        VALUES ('simulation-1', 'u-test', NULL)
      ''');
        legacy.execute('''
        INSERT INTO watchlist_simulation_observations (
          id, owner_user_id, simulation_id
        ) VALUES ('observation-1', 'u-test', 'simulation-1')
      ''');
        legacy.execute('PRAGMA user_version = 91');
      } finally {
        legacy.close();
      }

      final db = AppDatabase(
        DatabaseConnection(NativeDatabase(file, logStatements: false)),
      );
      addTearDown(db.close);

      final version = await db.customSelect('PRAGMA user_version').getSingle();
      expect(version.read<int>('user_version'), db.schemaVersion);

      final triggers = await db
          .customSelect("SELECT name FROM sqlite_master WHERE type = 'trigger'")
          .get()
          .then(
            (rows) => rows.map((row) => row.read<String>('name')).toSet(),
          );
      expect(
        triggers,
        isNot(contains('trg_watchlist_simulation_tombstone_insert')),
      );
      expect(
        triggers,
        isNot(contains('trg_watchlist_simulation_tombstone_cleanup')),
      );
      expect(
        triggers,
        contains('trg_watchlist_simulation_delete_cleanup'),
      );

      Future<int> observationCount() async => db
          .customSelect(
            'SELECT COUNT(*) AS count FROM watchlist_simulation_observations',
          )
          .getSingle()
          .then((row) => row.read<int>('count'));

      expect(await observationCount(), 1);
      await db.customStatement(
        'UPDATE watchlist_simulations SET deleted_at = 1700000000 '
        "WHERE id = 'simulation-1'",
      );
      expect(await observationCount(), 1);

      await db.customStatement(
        "DELETE FROM watchlist_simulations WHERE id = 'simulation-1'",
      );
      expect(await observationCount(), 0);
    },
  );
}
