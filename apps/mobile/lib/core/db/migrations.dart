import 'package:drift/drift.dart';

import 'app_database.dart';

/// Schema versions tracked by the app.
///
/// Bump on every schema change and add a corresponding step below. Never
/// renumber — version numbers are recorded in user databases.
class SchemaVersions {
  static const int v1Initial = 1;

  static const int current = v1Initial;
}

MigrationStrategy buildMigrationStrategy(AppDatabase db) {
  return MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
    },
    onUpgrade: (m, from, to) async {
      // Step migrations one version at a time so each step is small,
      // testable, and can rely on the previous schema state. As soon as
      // a real migration lands, replace this throw with a switch on `v`
      // inside `for (var v = from + 1; v <= to; v++)`.
      throw StateError(
        'No migration registered for schema upgrade from v$from to v$to.',
      );
    },
    beforeOpen: (details) async {
      // Foreign keys must be enabled per-connection — they are off by
      // default in SQLite/SQLCipher and the setting does not persist.
      await db.customStatement('PRAGMA foreign_keys = ON;');
    },
  );
}
