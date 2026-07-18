// On-device integration test (docs/development/testing-strategy.md section 6).
//
// This covers Task #11 beyond the headless flow test: the app is booted with
// a real file-backed AppDatabase, Backup & Restore is driven through the real
// Settings UI, and the restore runner uses BackupService against that same
// on-disk database. Only the platform file picker is replaced with a
// deterministic backup payload.
//
// Run:
//   flutter test integration_test/backup_restore_integration_test.dart -d macos
//   flutter test integration_test/backup_restore_integration_test.dart -d <android device>

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:naviwealth/core/backup/backup_codec.dart';
import 'package:naviwealth/core/backup/backup_service.dart';
import 'package:naviwealth/core/backup/providers.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/features/settings/ui/backup/backup_page.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../test/flow/support/app_harness.dart';
import '../test/flow/support/page_objects.dart';
import 'support/database_encryption_fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const sourceDbFileName = 'integration_backup_source.sqlite';
  const targetDbFileName = 'integration_backup_target.sqlite';
  const passphrase = 'correct horse battery staple';
  const deviceId = 'integration-device';

  Future<void> deleteDbFiles() async {
    final dir = await getApplicationDocumentsDirectory();
    for (final name in [sourceDbFileName, targetDbFileName]) {
      for (final suffix in [
        '',
        '-shm',
        '-wal',
        '-journal',
        '.encrypting',
        '.plaintext-backup',
      ]) {
        final file = File(p.join(dir.path, '$name$suffix'));
        if (file.existsSync()) file.deleteSync();
      }
    }
  }

  setUp(deleteDbFiles);
  tearDown(deleteDbFiles);

  testWidgets(
    'Backup & Restore imports encrypted bytes into the real app database',
    (tester) async {
      _installReceiveSharingIntentMocks();

      final sourceDb = AppDatabase.open(
        dbFileName: sourceDbFileName,
        encryptionKey: integrationDatabaseEncryptionKey,
      );
      var sourceClosed = false;
      addTearDown(() async {
        if (!sourceClosed) await sourceDb.close();
      });

      await _forceOpen(sourceDb);
      await _insertAccount(
        sourceDb,
        id: 'source-acct',
        name: 'Restored Checking',
        deviceId: deviceId,
      );
      final backupBytes = await BackupService(
        db: sourceDb,
        codec: BackupCodec(),
        outbox: DriftOutboxStore(sourceDb),
        deviceId: deviceId,
      ).exportBackup(passphrase: passphrase, overrideIterations: 1000);
      expect(backupBytes, isNotEmpty);

      await sourceDb.close();
      sourceClosed = true;

      final targetDb = AppDatabase.open(
        dbFileName: targetDbFileName,
        encryptionKey: integrationDatabaseEncryptionKey,
      );
      final data = FlowDataHarness(
        db: targetDb,
        outbox: InMemoryOutboxStore(),
        stamper: MutationStamper(
          currentUserId: () async => 'integration-user',
          deviceId: () async => deviceId,
          stampHlc: () async =>
              const Hlc(wallMillis: 1, counter: 0, nodeId: deviceId),
        ),
      );
      addTearDown(() async {
        await data.dispose();
      });

      await _forceOpen(targetDb);
      await _insertAccount(
        targetDb,
        id: 'stale-acct',
        name: 'Stale Local Account',
        deviceId: deviceId,
      );

      await bootApp(
        tester,
        liveData: data,
        extraOverrides: [
          backupRestoreFilePickerProvider.overrideWithValue(() async {
            return PickedBackupFile(
              name: 'naviwealth-integration-backup.bak',
              bytes: Uint8List.fromList(backupBytes),
            );
          }),
          backupRestoreRunnerProvider.overrideWith((ref) async {
            final service = BackupService(
              db: targetDb,
              codec: BackupCodec(),
              outbox: DriftOutboxStore(targetDb),
              deviceId: deviceId,
            );
            return ({
              required String passphrase,
              required Uint8List fileBytes,
            }) {
              return service.restoreBackup(
                passphrase: passphrase,
                fileBytes: fileBytes,
              );
            };
          }),
        ],
      );

      final shell = AppShell(tester)..expectMounted();
      await shell.openSettings();

      final settings = SettingsPageObject(tester);
      settings.expectLanded();
      await settings.openBackupAndRestore();

      final backup = BackupPageObject(tester);
      backup.expectLanded();
      await backup.importWithPassphrase(passphrase);
      backup.expectImportSucceeded(rows: 1);

      final accountIds = await _accountIds(targetDb);
      expect(accountIds, contains('source-acct'));
      expect(accountIds, isNot(contains('stale-acct')));
      expect(await DriftOutboxStore(targetDb).depth(), 1);
      debugPrint('backup: encrypted restore completed on file database');
      await closeApp(tester);
    },
  );

  testWidgets(
    'failed restore rollback survives closing and reopening the real database',
    (tester) async {
      final codec = BackupCodec();
      final sourceDb = AppDatabase.open(
        dbFileName: sourceDbFileName,
        encryptionKey: integrationDatabaseEncryptionKey,
      );
      var sourceClosed = false;
      addTearDown(() async {
        if (!sourceClosed) await sourceDb.close();
      });
      await _forceOpen(sourceDb);
      await _insertAccount(
        sourceDb,
        id: 'source-acct',
        name: 'Source Account',
        deviceId: deviceId,
      );
      final exported = await BackupService(
        db: sourceDb,
        codec: codec,
        outbox: DriftOutboxStore(sourceDb),
      ).exportBackup(passphrase: passphrase, overrideIterations: 1000);
      final envelope = BackupEnvelope.decodeBytes(exported);
      final plaintext = await codec.decrypt(
        passphrase: passphrase,
        envelope: envelope,
      );
      final payload =
          jsonDecode(utf8.decode(plaintext)) as Map<String, Object?>;
      final header = payload['header'] as Map<String, Object?>;
      final data = payload['data'] as Map<String, Object?>;
      final accounts = data['accounts'] as List<Object?>;
      accounts.add(<String, Object?>{'id': 'invalid-row'});
      (header['tables'] as Map<String, Object?>)['accounts'] = accounts.length;
      final invalidEnvelope = await codec.encrypt(
        passphrase: passphrase,
        plaintext: Uint8List.fromList(utf8.encode(jsonEncode(payload))),
        schemaVersion: sourceDb.schemaVersion,
        iterations: 1000,
      );
      await sourceDb.close();
      sourceClosed = true;

      final targetDb = AppDatabase.open(
        dbFileName: targetDbFileName,
        encryptionKey: integrationDatabaseEncryptionKey,
      );
      var targetClosed = false;
      addTearDown(() async {
        if (!targetClosed) await targetDb.close();
      });
      await _forceOpen(targetDb);
      await _insertAccount(
        targetDb,
        id: 'preserved-acct',
        name: 'Preserved Account',
        deviceId: deviceId,
      );
      await DriftOutboxStore(
        targetDb,
      ).enqueue(table: 'accounts', rowId: 'preserved-acct');

      await expectLater(
        BackupService(
          db: targetDb,
          codec: codec,
          outbox: DriftOutboxStore(targetDb),
        ).restoreBackup(
          passphrase: passphrase,
          fileBytes: invalidEnvelope.encodeBytes(),
        ),
        throwsA(anything),
      );
      await targetDb.close();
      targetClosed = true;

      final reopened = AppDatabase.open(
        dbFileName: targetDbFileName,
        encryptionKey: integrationDatabaseEncryptionKey,
      );
      addTearDown(reopened.close);
      expect(await _accountIds(reopened), <String>['preserved-acct']);
      final outboxRows = await reopened
          .customSelect('SELECT table_name, row_id FROM op_outbox')
          .get();
      expect(outboxRows, hasLength(1));
      expect(outboxRows.single.read<String>('table_name'), 'accounts');
      expect(outboxRows.single.read<String>('row_id'), 'preserved-acct');
      debugPrint('backup: failed restore rollback persisted after reopen');
    },
  );
}

void _installReceiveSharingIntentMocks() {
  const messages = MethodChannel('receive_sharing_intent/messages');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(messages, (call) async {
        return switch (call.method) {
          'getInitialMedia' => null,
          'reset' => null,
          _ => null,
        };
      });

  const codec = StandardMethodCodec();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMessageHandler('receive_sharing_intent/events-media', (
        message,
      ) async {
        final call = codec.decodeMethodCall(message);
        return switch (call.method) {
          'listen' || 'cancel' => codec.encodeSuccessEnvelope(null),
          _ => codec.encodeErrorEnvelope(code: 'unimplemented'),
        };
      });
}

Future<void> _forceOpen(AppDatabase db) async {
  await db.select(db.accounts).get();
}

Future<List<String>> _accountIds(AppDatabase db) async {
  final rows = await db
      .customSelect('SELECT id FROM accounts ORDER BY id')
      .get();
  return rows.map((row) => row.read<String>('id')).toList();
}

Future<void> _insertAccount(
  AppDatabase db, {
  required String id,
  required String name,
  required String deviceId,
}) async {
  const userId = 'integration-user';
  final hlc = Hlc(wallMillis: 1700000000000, counter: 0, nodeId: deviceId);
  await db.customStatement(
    'INSERT INTO accounts '
    '(id, type, name, currency, owner_user_id, updated_at, '
    'updated_by_device, hlc, deleted_at, archived, category) '
    'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?)',
    [
      id,
      'cash',
      name,
      'CNY',
      userId,
      DateTime.utc(2026, 6, 19).millisecondsSinceEpoch,
      deviceId,
      hlc.toString(),
      null,
      'asset',
    ],
  );
}
