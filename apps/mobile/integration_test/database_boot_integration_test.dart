// On-device integration test (docs/development/testing-strategy.md §6).
//
// Every headless test (test/ + test/integration/) uses NativeDatabase.memory
// via makeTestDatabase(), which bypasses the production connection: real
// file I/O, SQLCipher unlock, path_provider, the background-isolate open, and
// the on-disk migration to schemaVersion. This test closes that gap by opening the
// REAL AppDatabase through AppDatabase.open() on a real platform
// (run on macOS/Android, NOT the host `flutter test` VM) and proving a
// write survives a full close / reopen cycle.
//
// Run:
//   flutter test integration_test/database_boot_integration_test.dart -d macos
//   flutter test integration_test/ -d <android device>

import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/persistence/database_encryption.dart';
import 'package:naviwealth/core/persistence/database_encryption_platform.dart';
import 'package:naviwealth/core/security/flutter_secure_key_store.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'support/database_encryption_fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const dbFileName = 'integration_boot_test.sqlite';
  const keystoreDbFileName = 'integration_keystore_test.sqlite';
  final secureStore = FlutterSecureKeyStore();

  Future<void> deleteDbFiles() async {
    final dir = await getApplicationDocumentsDirectory();
    for (final name in <String>[dbFileName, keystoreDbFileName]) {
      final path = p.join(dir.path, name);
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
    await secureStore.delete(databaseEncryptionKeyStorageKey);
  }

  setUp(deleteDbFiles);
  tearDown(deleteDbFiles);

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
    debugPrint('database-encryption: sqlcipher available');

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
    debugPrint('database-encryption: encrypted header verified');

    // 3. Reopen the same file — the row must still be there, proving the
    //    write hit disk through the production connection, not memory.
    final reopened = AppDatabase.open(
      dbFileName: dbFileName,
      encryptionKey: integrationDatabaseEncryptionKey,
    );
    final rows = await reopened.select(reopened.accounts).get();
    expect(rows.map((r) => r.id), contains('boot-acct'));
    await reopened.close();
    debugPrint('database-encryption: correct key reopen verified');

    final wrongKey = integrationDatabaseEncryptionKey.replaceFirst('7a', '8b');
    final locked = AppDatabase.open(
      dbFileName: dbFileName,
      encryptionKey: wrongKey,
    );
    await expectLater(
      locked.customSelect('SELECT count(*) FROM accounts;').get(),
      throwsA(anything),
    );
    debugPrint('database-encryption: wrong key rejected');
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
    debugPrint('database-encryption: plaintext migration verified');
  });

  testWidgets(
    'Android production secure storage preserves and fails closed for the key',
    (_) async {
      if (!Platform.isAndroid) return;

      final firstKey = await resolveDatabaseEncryptionKey(
        store: secureStore,
        dbFileName: keystoreDbFileName,
      );
      expect(firstKey, isNotNull);
      expect(DatabaseEncryptionKeyManager.isValidKey(firstKey!), isTrue);

      final db = AppDatabase.open(
        dbFileName: keystoreDbFileName,
        encryptionKey: firstKey,
      );
      await db.select(db.accounts).get();
      await db.close();

      final secondKey = await resolveDatabaseEncryptionKey(
        store: FlutterSecureKeyStore(),
        dbFileName: keystoreDbFileName,
      );
      expect(secondKey, firstKey);
      debugPrint('database-encryption: android keystore key persisted');

      await secureStore.delete(databaseEncryptionKeyStorageKey);
      await expectLater(
        resolveDatabaseEncryptionKey(
          store: FlutterSecureKeyStore(),
          dbFileName: keystoreDbFileName,
        ),
        throwsA(
          isA<DatabaseEncryptionException>().having(
            (error) => error.code,
            'code',
            DatabaseEncryptionFailureCode.keyMissing,
          ),
        ),
      );
      debugPrint('database-encryption: missing keystore key failed closed');

      await secureStore.write(databaseEncryptionKeyStorageKey, firstKey);
      final reopened = AppDatabase.open(
        dbFileName: keystoreDbFileName,
        encryptionKey: firstKey,
      );
      await reopened.select(reopened.accounts).get();
      await reopened.close();
      debugPrint('database-encryption: restored keystore key reopened');
    },
  );
}
