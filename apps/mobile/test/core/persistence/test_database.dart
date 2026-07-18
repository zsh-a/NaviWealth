import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import 'package:naviwealth/core/persistence/app_database.dart';

/// Builds an in-memory [AppDatabase] suitable for unit tests.
///
/// Tests deliberately use an unkeyed in-memory database. Bypassing the
/// platform-aware connection layer is intentional — focused native tests and
/// integration_test cover SQLCipher keys and real encrypted files.
AppDatabase makeTestDatabase() {
  // Tests legitimately spin up many independent in-memory databases;
  // silence drift's "multiple databases" warning so test output stays
  // readable. Production code only ever creates one.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  return AppDatabase(
    DatabaseConnection(NativeDatabase.memory(logStatements: false)),
  );
}
