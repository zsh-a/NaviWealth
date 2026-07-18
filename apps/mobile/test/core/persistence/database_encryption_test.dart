import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/persistence/connection_native.dart';
import 'package:naviwealth/core/persistence/database_encryption.dart';
import 'package:naviwealth/core/persistence/database_encryption_platform_native.dart';
import 'package:naviwealth/core/security/in_memory_key_store.dart';

const _key =
    '00112233445566778899aabbccddeeff'
    '102132435465768798a9bacbdcedfe0f';
const _wrongKey =
    'ffeeddccbbaa99887766554433221100'
    '0ffeedccbbaa99887766554433221120';

void main() {
  group('DatabaseEncryptionKeyManager', () {
    test('creates one deterministic 256-bit key and then reuses it', () async {
      final store = InMemoryKeyStore();
      var generations = 0;
      final manager = DatabaseEncryptionKeyManager(
        store,
        randomBytes: (length) {
          generations++;
          return List<int>.generate(length, (index) => index);
        },
      );

      final first = await manager.loadOrCreate(encryptedDatabaseExists: false);
      final second = await manager.loadOrCreate(encryptedDatabaseExists: true);

      expect(first, hasLength(64));
      expect(second, first);
      expect(generations, 1);
      expect(await store.read(databaseEncryptionKeyStorageKey), first);
    });

    test('never replaces a missing key beside encrypted bytes', () async {
      final store = InMemoryKeyStore();
      final manager = DatabaseEncryptionKeyManager(
        store,
        randomBytes: (_) => List<int>.filled(32, 7),
      );

      await expectLater(
        manager.loadOrCreate(encryptedDatabaseExists: true),
        throwsA(
          isA<DatabaseEncryptionException>().having(
            (error) => error.code,
            'code',
            DatabaseEncryptionFailureCode.keyMissing,
          ),
        ),
      );
      expect(await store.read(databaseEncryptionKeyStorageKey), isNull);
    });

    test('rejects a malformed stored key without repairing it', () async {
      final store = InMemoryKeyStore({
        databaseEncryptionKeyStorageKey: 'not-a-key',
      });

      await expectLater(
        DatabaseEncryptionKeyManager(
          store,
        ).loadOrCreate(encryptedDatabaseExists: false),
        throwsA(
          isA<DatabaseEncryptionException>().having(
            (error) => error.code,
            'code',
            DatabaseEncryptionFailureCode.invalidKey,
          ),
        ),
      );
      expect(await store.read(databaseEncryptionKeyStorageKey), 'not-a-key');
    });
  });

  group('native SQLCipher database', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('naviwealth-sqlcipher-');
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test(
      'writes encrypted bytes and reopens only with the correct key',
      () async {
        final file = File('${tempDir.path}/encrypted.sqlite');
        final db = AppDatabase(encryptedNativeDatabase(file, _key));
        await db.customStatement(
          'CREATE TABLE encryption_fixture (value TEXT NOT NULL);',
        );
        await db.customStatement(
          'INSERT INTO encryption_fixture (value) VALUES (?);',
          const ['preserved'],
        );
        await db.close();

        expect(_hasPlaintextHeader(file), isFalse);
        final encryptedDigest = sha256.convert(file.readAsBytesSync());

        final reopened = AppDatabase(encryptedNativeDatabase(file, _key));
        final values = await reopened
            .customSelect('SELECT value FROM encryption_fixture;')
            .get();
        expect(values.single.read<String>('value'), 'preserved');
        await reopened.close();

        final wrong = AppDatabase(encryptedNativeDatabase(file, _wrongKey));
        await expectLater(
          wrong.customSelect('SELECT value FROM encryption_fixture;').get(),
          throwsA(anything),
        );
        await _closeIgnoringFailure(wrong);

        expect(sha256.convert(file.readAsBytesSync()), encryptedDigest);
      },
    );

    test('migrates a plaintext database without changing its rows', () async {
      final file = File('${tempDir.path}/legacy.sqlite');
      final plaintext = AppDatabase(
        DatabaseConnection(NativeDatabase(file, logStatements: false)),
      );
      await plaintext.customStatement(
        'CREATE TABLE encryption_fixture (value TEXT NOT NULL);',
      );
      await plaintext.customStatement(
        'INSERT INTO encryption_fixture (value) VALUES (?);',
        const ['legacy-row'],
      );
      final schemaVersion = plaintext.schemaVersion;
      await plaintext.close();
      expect(_hasPlaintextHeader(file), isTrue);

      prepareEncryptedDatabaseFile(file.path, _key);

      expect(_hasPlaintextHeader(file), isFalse);
      expect(File('${file.path}.plaintext-backup').existsSync(), isFalse);
      expect(File('${file.path}.encrypting').existsSync(), isFalse);

      final migrated = AppDatabase(encryptedNativeDatabase(file, _key));
      final values = await migrated
          .customSelect('SELECT value FROM encryption_fixture;')
          .get();
      final version = await migrated
          .customSelect('PRAGMA user_version;')
          .getSingle();
      expect(values.single.read<String>('value'), 'legacy-row');
      expect(version.read<int>('user_version'), schemaVersion);
      await migrated.close();
    });

    test('finishes a validated interrupted migration swap', () async {
      final original = File('${tempDir.path}/interrupted.sqlite');
      final plaintext = AppDatabase(
        DatabaseConnection(NativeDatabase(original, logStatements: false)),
      );
      await plaintext.customStatement(
        'CREATE TABLE encryption_fixture (value TEXT NOT NULL);',
      );
      await plaintext.customStatement(
        'INSERT INTO encryption_fixture (value) VALUES (?);',
        const ['survives-interruption'],
      );
      await plaintext.close();

      final stagedPlaintext = File('${tempDir.path}/staged.sqlite');
      original.copySync(stagedPlaintext.path);
      prepareEncryptedDatabaseFile(stagedPlaintext.path, _key);
      stagedPlaintext.renameSync('${original.path}.encrypting');
      original.renameSync('${original.path}.plaintext-backup');
      expect(original.existsSync(), isFalse);

      prepareEncryptedDatabaseFile(original.path, _key);

      final recovered = AppDatabase(encryptedNativeDatabase(original, _key));
      final values = await recovered
          .customSelect('SELECT value FROM encryption_fixture;')
          .get();
      expect(values.single.read<String>('value'), 'survives-interruption');
      expect(File('${original.path}.plaintext-backup').existsSync(), isFalse);
      await recovered.close();
    });

    test(
      'falls back to the plaintext backup when staged bytes are corrupt',
      () async {
        final original = File('${tempDir.path}/corrupt-stage.sqlite');
        final plaintext = AppDatabase(
          DatabaseConnection(NativeDatabase(original, logStatements: false)),
        );
        await plaintext.customStatement(
          'CREATE TABLE encryption_fixture (value TEXT NOT NULL);',
        );
        await plaintext.customStatement(
          'INSERT INTO encryption_fixture (value) VALUES (?);',
          const ['backup-row'],
        );
        await plaintext.close();

        original.renameSync('${original.path}.plaintext-backup');
        File(
          '${original.path}.encrypting',
        ).writeAsBytesSync(List<int>.filled(4096, 0x5a));

        prepareEncryptedDatabaseFile(original.path, _key);

        final recovered = AppDatabase(encryptedNativeDatabase(original, _key));
        final values = await recovered
            .customSelect('SELECT value FROM encryption_fixture;')
            .get();
        expect(values.single.read<String>('value'), 'backup-row');
        expect(_hasPlaintextHeader(original), isFalse);
        await recovered.close();
      },
    );

    test(
      'reset deletes only known database artifacts and the device key',
      () async {
        final databasePath = '${tempDir.path}/reset.sqlite';
        for (final path in databaseArtifactPaths(databasePath)) {
          File(path).writeAsStringSync('fixture');
        }
        final unrelated = File('${tempDir.path}/keep-me.txt')
          ..writeAsStringSync('keep');
        final store = InMemoryKeyStore({
          databaseEncryptionKeyStorageKey: _key,
          'unrelated-secret': 'keep',
        });

        await resetEncryptedDatabaseAtPath(
          store: store,
          databasePath: databasePath,
        );

        for (final path in databaseArtifactPaths(databasePath)) {
          expect(File(path).existsSync(), isFalse, reason: path);
        }
        expect(unrelated.existsSync(), isTrue);
        expect(await store.read(databaseEncryptionKeyStorageKey), isNull);
        expect(await store.read('unrelated-secret'), 'keep');
      },
    );
  });
}

bool _hasPlaintextHeader(File file) {
  final bytes = file.readAsBytesSync();
  return bytes.length >= 16 &&
      String.fromCharCodes(bytes.take(16)) == 'SQLite format 3\u0000';
}

Future<void> _closeIgnoringFailure(AppDatabase database) async {
  try {
    await database.close();
  } on Object {
    // A failed background-isolate open can also make close report that error.
  }
}
