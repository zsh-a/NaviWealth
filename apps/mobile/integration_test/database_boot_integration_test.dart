// On-device integration test (docs/development/testing-strategy.md §6).
//
// Every headless test (test/ + test/integration/) uses NativeDatabase.memory
// via makeTestDatabase(), which bypasses the production connection: real
// file I/O, SQLCipher unlock, path_provider, the background-isolate open, and
// the on-disk migration to schemaVersion. This test closes that gap by opening the
// REAL AppDatabase through openAppConnection() on a real platform
// (run on macOS/Android, NOT the host `flutter test` VM) and proving a
// write survives a full close / reopen cycle.
//
// Run:
//   flutter test integration_test/database_boot_integration_test.dart -d macos
//   flutter test integration_test/ -d <android device>

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'support/database_encryption_fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const dbFileName = 'integration_boot_test.sqlite';

  Future<void> deleteDbFile() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, dbFileName);
    for (final suffix in <String>[
      '',
      '-wal',
      '-shm',
      '-journal',
      '.encrypting',
      '.plaintext-backup',
    ]) {
      final file = File('$path$suffix');
      if (file.existsSync()) file.deleteSync();
    }
  }

  setUp(deleteDbFile);
  tearDown(deleteDbFile);

  testWidgets('real file-backed AppDatabase migrates, persists, and reopens', (
    tester,
  ) async {
    // 1. Open the production native connection (path_provider + a real
    //    file + createInBackground) and run migrations to schemaVersion.
    final db = AppDatabase.open(
      dbFileName: dbFileName,
      encryptionKey: integrationDatabaseEncryptionKey,
    );
    expect(db.schemaVersion, greaterThan(0));
    final cipherVersion = await db
        .customSelect('PRAGMA cipher_version;')
        .getSingle();
    expect(cipherVersion.data.values.single, isNotEmpty);

    // A query forces the LazyDatabase to actually open + migrate.
    final initial = await db.select(db.accounts).get();
    expect(initial, isEmpty);

    // 2. Write a row to the real file.
    await db
        .into(db.accounts)
        .insert(
          AccountsCompanion.insert(
            id: 'boot-acct',
            type: AccountCategory.bank,
            name: 'Boot Account',
            currency: 'CNY',
            ownerUserId: 'u-test',
            updatedAt: DateTime.utc(2026),
            updatedByDevice: 'dev-test',
            hlc: const Hlc(wallMillis: 1, counter: 0, nodeId: 'dev-test'),
          ),
        );
    await db.close();

    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, dbFileName));
    final header = String.fromCharCodes(file.readAsBytesSync().take(16));
    expect(header, isNot('SQLite format 3\u0000'));

    // 3. Reopen the same file — the row must still be there, proving the
    //    write hit disk through the production connection, not memory.
    final reopened = AppDatabase.open(
      dbFileName: dbFileName,
      encryptionKey: integrationDatabaseEncryptionKey,
    );
    final rows = await reopened.select(reopened.accounts).get();
    expect(rows.map((r) => r.id), contains('boot-acct'));
    await reopened.close();

    final wrongKey = integrationDatabaseEncryptionKey.replaceFirst('7a', '8b');
    final locked = AppDatabase.open(
      dbFileName: dbFileName,
      encryptionKey: wrongKey,
    );
    await expectLater(
      locked.customSelect('SELECT count(*) FROM accounts;').get(),
      throwsA(anything),
    );
    try {
      await locked.close();
    } on Object {
      // A failed background-isolate open can also make close report the error.
    }
  });

  testWidgets('legacy plaintext rows migrate to SQLCipher in place', (
    tester,
  ) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, dbFileName));
    final legacy = AppDatabase(
      DatabaseConnection(NativeDatabase(file, logStatements: false)),
    );
    await legacy.customStatement(
      'CREATE TABLE encryption_migration_fixture (value TEXT NOT NULL);',
    );
    await legacy.customStatement(
      'INSERT INTO encryption_migration_fixture (value) VALUES (?);',
      const ['android-legacy-row'],
    );
    await legacy.close();
    expect(
      String.fromCharCodes(file.readAsBytesSync().take(16)),
      'SQLite format 3\u0000',
    );

    final migrated = AppDatabase.open(
      dbFileName: dbFileName,
      encryptionKey: integrationDatabaseEncryptionKey,
    );
    final row = await migrated
        .customSelect('SELECT value FROM encryption_migration_fixture;')
        .getSingle();
    expect(row.read<String>('value'), 'android-legacy-row');
    await migrated.close();

    expect(
      String.fromCharCodes(file.readAsBytesSync().take(16)),
      isNot('SQLite format 3\u0000'),
    );
    expect(File('${file.path}.encrypting').existsSync(), isFalse);
    expect(File('${file.path}.plaintext-backup').existsSync(), isFalse);
  });
}
