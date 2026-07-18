// Android-only, two-process recovery test.
//
// The interrupt phase starts a real restore against the production file-backed
// database. CI force-stops the app immediately after BackupService logs that
// the archive tables were cleared inside its transaction. The verify phase is
// a fresh app process that opens the same database and proves SQLite rolled the
// uncommitted wipe back. See tool/run-android-backup-interruption.sh.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:naviwealth/core/backup/backup_codec.dart';
import 'package:naviwealth/core/backup/backup_service.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const _phase = String.fromEnvironment('BACKUP_INTERRUPTION_PHASE');
const _sourceDbFileName = 'integration_interrupt_source.sqlite';
const _targetDbFileName = 'integration_interrupt_target.sqlite';
const _passphrase = 'android process interruption fixture';
const _deviceId = 'android-interruption-device';
const _incomingAccountCount = 20000;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'interrupt restore after the destructive wipe begins',
    (_) async {
      await _deleteDbFiles();
      final codec = BackupCodec();
      final sourceDb = AppDatabase.open(dbFileName: _sourceDbFileName);
      await _forceOpen(sourceDb);
      await _insertAccount(
        sourceDb,
        id: 'incoming-template',
        name: 'Incoming Template',
      );
      final exported = await BackupService(
        db: sourceDb,
        codec: codec,
        outbox: DriftOutboxStore(sourceDb),
      ).exportBackup(passphrase: _passphrase, overrideIterations: 1000);
      final envelope = BackupEnvelope.decodeBytes(exported);
      final plaintext = await codec.decrypt(
        passphrase: _passphrase,
        envelope: envelope,
      );
      final payload =
          jsonDecode(utf8.decode(plaintext)) as Map<String, Object?>;
      final header = payload['header'] as Map<String, Object?>;
      final data = payload['data'] as Map<String, Object?>;
      final template = Map<String, Object?>.from(
        (data['accounts'] as List<Object?>).single as Map<String, Object?>,
      );
      final incomingAccounts = <Map<String, Object?>>[
        for (var index = 0; index < _incomingAccountCount; index++)
          <String, Object?>{
            ...template,
            'id': 'incoming-$index',
            'name': 'Incoming $index',
          },
      ];
      data['accounts'] = incomingAccounts;
      (header['tables'] as Map<String, Object?>)['accounts'] =
          incomingAccounts.length;
      final largeEnvelope = await codec.encrypt(
        passphrase: _passphrase,
        plaintext: Uint8List.fromList(utf8.encode(jsonEncode(payload))),
        schemaVersion: sourceDb.schemaVersion,
        iterations: 1000,
      );
      await sourceDb.close();

      final targetDb = AppDatabase.open(dbFileName: _targetDbFileName);
      addTearDown(targetDb.close);
      await _forceOpen(targetDb);
      await _insertAccount(
        targetDb,
        id: 'preserved-acct',
        name: 'Preserved Across Force Stop',
      );
      await DriftOutboxStore(
        targetDb,
      ).enqueue(table: 'accounts', rowId: 'preserved-acct');

      await BackupService(
        db: targetDb,
        codec: codec,
        outbox: DriftOutboxStore(targetDb),
      ).restoreBackup(
        passphrase: _passphrase,
        fileBytes: largeEnvelope.encodeBytes(),
      );

      fail('Restore committed before the Android force-stop was delivered.');
    },
    skip: _phase != 'interrupt' || !Platform.isAndroid,
  );

  testWidgets(
    'fresh process observes rollback after interrupted restore',
    (_) async {
      final dbFile = await _dbFile(_targetDbFileName);
      expect(
        dbFile.existsSync(),
        isTrue,
        reason: 'The interrupt phase database must survive process restart.',
      );

      final reopened = AppDatabase.open(dbFileName: _targetDbFileName);
      await _forceOpen(reopened);
      expect(await _accountIds(reopened), <String>['preserved-acct']);
      final outboxRows = await reopened
          .customSelect('SELECT table_name, row_id FROM op_outbox')
          .get();
      expect(outboxRows, hasLength(1));
      expect(outboxRows.single.read<String>('table_name'), 'accounts');
      expect(outboxRows.single.read<String>('row_id'), 'preserved-acct');
      debugPrint(
        'backup: interruption verification preserved account + outbox',
      );
      await reopened.close();
      await _deleteDbFiles();
    },
    skip: _phase != 'verify' || !Platform.isAndroid,
  );
}

Future<File> _dbFile(String name) async {
  final dir = await getApplicationDocumentsDirectory();
  return File(p.join(dir.path, name));
}

Future<void> _deleteDbFiles() async {
  for (final name in [_sourceDbFileName, _targetDbFileName]) {
    final base = await _dbFile(name);
    for (final suffix in ['', '-shm', '-wal']) {
      final file = File('${base.path}$suffix');
      if (file.existsSync()) file.deleteSync();
    }
  }
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
}) async {
  const hlc = Hlc(wallMillis: 1700000000000, counter: 0, nodeId: _deviceId);
  await db.customStatement(
    'INSERT INTO accounts '
    '(id, type, name, currency, owner_user_id, updated_at, '
    'updated_by_device, hlc, deleted_at, archived, category) '
    'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?)',
    <Object?>[
      id,
      'cash',
      name,
      'CNY',
      'integration-user',
      DateTime.utc(2026, 7, 18).millisecondsSinceEpoch,
      _deviceId,
      hlc.toString(),
      null,
      'asset',
    ],
  );
}
