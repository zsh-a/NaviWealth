import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import 'package:naviwealth/core/persistence/app_database.dart';

/// Builds an in-memory [AppDatabase] suitable for unit tests.
///
/// Tests run on the host (no SQLCipher binary). Bypassing the
/// platform-aware connection layer is intentional — coverage of the
/// SQLCipher PRAGMA path lives in integration_test/, not here.
AppDatabase makeTestDatabase() {
  // Tests legitimately spin up many independent in-memory databases;
  // silence drift's "multiple databases" warning so test output stays
  // readable. Production code only ever creates one.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  return AppDatabase(
    DatabaseConnection(NativeDatabase.memory(logStatements: false)),
  );
}
