import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/backup/backup_codec.dart';
import 'package:naviwealth/core/backup/backup_service.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/op.dart';
import 'package:naviwealth/data/db/app_database.dart';
import 'package:naviwealth/data/domain/hlc.dart';

import '../../data/db/test_database.dart';
import '../sync/_outbox_test_ext.dart';

void main() {
  const testIterations = 1000; // fast for tests
  const testPassphrase = 'test-passphrase-123';
  const testDeviceId = '00000000-0000-0000-0000-000000000001';

  late BackupService service;
  late BackupCodec codec;
  late InMemoryOutboxStore outbox;

  setUp(() {
    codec = BackupCodec();
    outbox = InMemoryOutboxStore();
  });

  /// Insert a minimal test account row into the database.
  Future<void> insertTestAccount(
    AppDatabase db, {
    String id = 'acct-1',
    String name = 'Test Account',
    String type = 'cash',
    String currency = 'CNY',
    int? deletedAtMs,
  }) async {
    final now = DateTime.utc(2026, 1, 1).millisecondsSinceEpoch;
    const hlc = Hlc(wallMillis: 1700000000000, counter: 0, nodeId: testDeviceId);
    await db.customStatement(
      'INSERT INTO accounts '
      '(id, type, name, currency, owner_user_id, updated_at, updated_by_device, hlc, deleted_at, archived, category) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?)',
      [id, type, name, currency, 'user-1', now, testDeviceId, hlc.toString(), deletedAtMs, 'asset'],
    );
  }

  /// Insert a minimal test tag row.
  Future<void> insertTestTag(
    AppDatabase db, {
    String id = 'tag-1',
    String name = 'Test Tag',
  }) async {
    final now = DateTime.utc(2026, 1, 1).toIso8601String();
    const hlc = Hlc(wallMillis: 1700000000001, counter: 0, nodeId: testDeviceId);
    await db.customStatement(
      'INSERT INTO tags '
      '(id, name, kind, owner_user_id, updated_at, updated_by_device, hlc) '
      'VALUES (?, ?, ?, ?, ?, ?, ?)',
      [id, name, 'generic', 'user-1', now, testDeviceId, hlc.toString()],
    );
  }

  /// Count rows in a table.
  Future<int> countRows(AppDatabase db, String table) async {
    final row =
        await db.customSelect('SELECT COUNT(*) AS c FROM $table').getSingle();
    return row.read<int>('c');
  }

  BackupService makeService(AppDatabase db) {
    return BackupService(
      db: db,
      codec: codec,
      outbox: outbox,
      deviceId: testDeviceId,
      stampHlc: () async => Hlc(
        wallMillis: DateTime.now().millisecondsSinceEpoch,
        counter: 0,
        nodeId: testDeviceId,
      ),
    );
  }

  group('BackupService', () {
    test('export produces valid envelope that decrypts to correct JSON',
        () async {
      final db = makeTestDatabase();
      addTearDown(db.close);

      await insertTestAccount(db);
      await insertTestTag(db);

      service = makeService(db);
      final bytes = await service.exportBackup(
        passphrase: testPassphrase,
        overrideIterations: testIterations,
      );

      // Verify the bytes decode to a valid envelope.
      final envelope = BackupEnvelope.decodeBytes(bytes);
      expect(envelope.schemaVersion, db.schemaVersion);

      // Decrypt and parse the payload.
      final plaintext = await codec.decrypt(
        passphrase: testPassphrase,
        envelope: envelope,
      );
      final json = jsonDecode(utf8.decode(plaintext)) as Map<String, Object?>;

      // Verify header.
      final header = json['header'] as Map<String, Object?>;
      expect(header['magic'], 'naviwealth.backup.v1');
      expect(header['schemaVersion'], db.schemaVersion);

      // Verify data contains our rows.
      final data = json['data'] as Map<String, Object?>;
      final accounts = data['accounts'] as List<Object?>;
      expect(accounts.length, 1);
      expect((accounts[0] as Map)['id'], 'acct-1');
      expect((accounts[0] as Map)['name'], 'Test Account');

      final tags = data['tags'] as List<Object?>;
      expect(tags.length, 1);
      expect((tags[0] as Map)['id'], 'tag-1');
    });

    test('round-trip: export then restore into fresh database', () async {
      final sourceDb = makeTestDatabase();
      addTearDown(sourceDb.close);

      await insertTestAccount(sourceDb, id: 'acct-1', name: 'Source Account');
      await insertTestAccount(
        sourceDb,
        id: 'acct-2',
        name: 'Another Account',
        currency: 'USD',
      );
      await insertTestTag(sourceDb, id: 'tag-1', name: 'Important');

      service = makeService(sourceDb);
      final bytes = await service.exportBackup(
        passphrase: testPassphrase,
        overrideIterations: testIterations,
      );

      // Restore into a fresh database.
      final targetDb = makeTestDatabase();
      addTearDown(targetDb.close);

      final restoreService = makeService(targetDb);
      final result = await restoreService.restoreBackup(
        passphrase: testPassphrase,
        fileBytes: bytes,
      );

      // Verify row counts.
      expect(result.tableCounts['accounts'], 2);
      expect(result.tableCounts['tags'], 1);

      // Verify actual data.
      expect(await countRows(targetDb, 'accounts'), 2);
      expect(await countRows(targetDb, 'tags'), 1);
    });

    test('wrong passphrase throws BackupAuthenticationException', () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      await insertTestAccount(db);

      service = makeService(db);
      final bytes = await service.exportBackup(
        passphrase: testPassphrase,
        overrideIterations: testIterations,
      );

      final restoreService = makeService(makeTestDatabase());
      expect(
        () => restoreService.restoreBackup(
          passphrase: 'wrong-passphrase',
          fileBytes: bytes,
        ),
        throwsA(isA<BackupAuthenticationException>()),
      );
    });

    test('newer schema version throws BackupSchemaTooNewException', () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      await insertTestAccount(db);

      service = makeService(db);
      final bytes = await service.exportBackup(
        passphrase: testPassphrase,
        overrideIterations: testIterations,
      );

      // Tamper with the envelope to set a higher schema version.
      final envelope = BackupEnvelope.decodeBytes(bytes);
      final tampered = BackupEnvelope(
        salt: envelope.salt,
        nonce: envelope.nonce,
        ciphertext: envelope.ciphertext,
        mac: envelope.mac,
        createdAt: envelope.createdAt,
        schemaVersion: 999,
        iterations: envelope.iterations,
      );
      final tamperedBytes = tampered.encodeBytes();

      final restoreService = makeService(makeTestDatabase());
      expect(
        () => restoreService.restoreBackup(
          passphrase: testPassphrase,
          fileBytes: tamperedBytes,
        ),
        throwsA(isA<BackupSchemaTooNewException>()),
      );
    });

    test('restore clears existing data before inserting', () async {
      // Source has one account.
      final sourceDb = makeTestDatabase();
      addTearDown(sourceDb.close);
      await insertTestAccount(sourceDb, id: 'source-acct');

      service = makeService(sourceDb);
      final bytes = await service.exportBackup(
        passphrase: testPassphrase,
        overrideIterations: testIterations,
      );

      // Target has a different account.
      final targetDb = makeTestDatabase();
      addTearDown(targetDb.close);
      await insertTestAccount(targetDb, id: 'target-acct', name: 'Old Account');

      final restoreService = makeService(targetDb);
      await restoreService.restoreBackup(
        passphrase: testPassphrase,
        fileBytes: bytes,
      );

      // Only the source account should exist.
      expect(await countRows(targetDb, 'accounts'), 1);
      final rows =
          await targetDb.customSelect('SELECT id FROM accounts').get();
      expect(rows.single.read<String>('id'), 'source-acct');
    });

    test('restore enqueues ops into outbox', () async {
      final sourceDb = makeTestDatabase();
      addTearDown(sourceDb.close);
      await insertTestAccount(sourceDb, id: 'acct-1');
      await insertTestTag(sourceDb, id: 'tag-1');

      service = makeService(sourceDb);
      final bytes = await service.exportBackup(
        passphrase: testPassphrase,
        overrideIterations: testIterations,
      );

      final targetDb = makeTestDatabase();
      addTearDown(targetDb.close);

      final restoreService = makeService(targetDb);
      await restoreService.restoreBackup(
        passphrase: testPassphrase,
        fileBytes: bytes,
      );

      // Verify ops were enqueued.
      final ops = await outbox.peekBatch();
      expect(ops.length, 2); // 1 account + 1 tag

      // All ops should be inserts.
      for (final op in ops) {
        expect(op.opType, OpType.insert);
        expect(op.deviceId, testDeviceId);
      }

      // Ops should reference the correct tables.
      final tableNames = ops.map((o) => o.tableName).toSet();
      expect(tableNames, containsAll(['accounts', 'tags']));
    });

    test('soft-deleted rows (tombstones) are included in backup', () async {
      final sourceDb = makeTestDatabase();
      addTearDown(sourceDb.close);
      await insertTestAccount(sourceDb, id: 'acct-alive');
      // Insert tombstone using numeric timestamp (Drift stores DateTime as int).
      final deletedAtMs = DateTime.utc(2026, 6, 1).millisecondsSinceEpoch;
      final now = DateTime.utc(2026, 1, 1).toIso8601String();
      const hlc = Hlc(wallMillis: 1700000000002, counter: 0, nodeId: testDeviceId);
      await sourceDb.customStatement(
        'INSERT INTO accounts '
        '(id, type, name, currency, owner_user_id, updated_at, updated_by_device, hlc, deleted_at, archived, category) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?)',
        ['acct-deleted', 'cash', 'Deleted Account', 'CNY', 'user-1', now, testDeviceId, hlc.toString(), deletedAtMs, 'asset'],
      );

      service = makeService(sourceDb);
      final bytes = await service.exportBackup(
        passphrase: testPassphrase,
        overrideIterations: testIterations,
      );

      // Verify both rows are in the backup.
      final envelope = BackupEnvelope.decodeBytes(bytes);
      final plaintext = await codec.decrypt(
        passphrase: testPassphrase,
        envelope: envelope,
      );
      final json = jsonDecode(utf8.decode(plaintext)) as Map<String, Object?>;
      final data = json['data'] as Map<String, Object?>;
      final accounts = data['accounts'] as List<Object?>;
      expect(accounts.length, 2);

      // Restore and verify tombstone is preserved.
      final targetDb = makeTestDatabase();
      addTearDown(targetDb.close);

      final restoreService = makeService(targetDb);
      await restoreService.restoreBackup(
        passphrase: testPassphrase,
        fileBytes: bytes,
      );

      expect(await countRows(targetDb, 'accounts'), 2);
      final rows = await targetDb
          .customSelect(
            'SELECT id, deleted_at FROM accounts ORDER BY id',
          )
          .get();
      expect(rows[0].read<String>('id'), 'acct-alive');
      expect(rows[0].readNullable<DateTime>('deleted_at'), isNull);
      expect(rows[1].read<String>('id'), 'acct-deleted');
      expect(rows[1].readNullable<DateTime>('deleted_at'), isNotNull);
    });

    test('pauseSync and resumeSync callbacks are invoked', () async {
      final sourceDb = makeTestDatabase();
      addTearDown(sourceDb.close);
      await insertTestAccount(sourceDb);

      service = makeService(sourceDb);
      final bytes = await service.exportBackup(
        passphrase: testPassphrase,
        overrideIterations: testIterations,
      );

      var pauseCalled = false;
      var resumeCalled = false;

      final targetDb = makeTestDatabase();
      addTearDown(targetDb.close);

      final restoreService = makeService(targetDb);
      await restoreService.restoreBackup(
        passphrase: testPassphrase,
        fileBytes: bytes,
        pauseSync: () => pauseCalled = true,
        resumeSync: () => resumeCalled = true,
      );

      expect(pauseCalled, isTrue);
      expect(resumeCalled, isTrue);
    });

    test('resumeSync is NOT called when decryption fails before pause',
        () async {
      final sourceDb = makeTestDatabase();
      addTearDown(sourceDb.close);
      await insertTestAccount(sourceDb);

      service = makeService(sourceDb);
      final bytes = await service.exportBackup(
        passphrase: testPassphrase,
        overrideIterations: testIterations,
      );

      var resumeCalled = false;

      // Restore with wrong passphrase — decryption fails before pauseSync,
      // so resumeSync should NOT be called.
      final targetDb = makeTestDatabase();
      addTearDown(targetDb.close);

      final restoreService = makeService(targetDb);
      try {
        await restoreService.restoreBackup(
          passphrase: 'wrong',
          fileBytes: bytes,
          resumeSync: () => resumeCalled = true,
        );
      } catch (_) {
        // Expected.
      }

      expect(resumeCalled, isFalse);
    });
  });
}
