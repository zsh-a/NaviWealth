import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/auth/domain_scope.dart';
import 'package:naviwealth/core/backup/backup_codec.dart';
import 'package:naviwealth/core/backup/backup_service.dart';
import 'package:naviwealth/core/backup/backup_table_registry.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/hlc.dart';

import '../../core/persistence/test_database.dart';

void main() {
  const testIterations = 1000; // fast for tests
  const testPassphrase = 'test-passphrase-123';
  const testDeviceId = '00000000-0000-0000-0000-000000000001';

  late BackupService service;
  late BackupCodec codec;

  setUp(() {
    codec = BackupCodec();
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
    const hlc = Hlc(
      wallMillis: 1700000000000,
      counter: 0,
      nodeId: testDeviceId,
    );
    await db.customStatement(
      'INSERT INTO accounts '
      '(id, type, name, currency, owner_user_id, updated_at, updated_by_device, hlc, deleted_at, archived, category) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?)',
      [
        id,
        type,
        name,
        currency,
        'user-1',
        now,
        testDeviceId,
        hlc.toString(),
        deletedAtMs,
        'asset',
      ],
    );
  }

  /// Insert a minimal test tag row.
  Future<void> insertTestTag(
    AppDatabase db, {
    String id = 'tag-1',
    String name = 'Test Tag',
  }) async {
    final now = DateTime.utc(2026, 1, 1).toIso8601String();
    const hlc = Hlc(
      wallMillis: 1700000000001,
      counter: 0,
      nodeId: testDeviceId,
    );
    await db.customStatement(
      'INSERT INTO tags '
      '(id, name, kind, owner_user_id, updated_at, updated_by_device, hlc) '
      'VALUES (?, ?, ?, ?, ?, ?, ?)',
      [id, name, 'generic', 'user-1', now, testDeviceId, hlc.toString()],
    );
  }

  Future<void> insertTestLiability(AppDatabase db) async {
    final now = DateTime.utc(2026, 1, 1).millisecondsSinceEpoch;
    const hlc = Hlc(
      wallMillis: 1700000000003,
      counter: 0,
      nodeId: testDeviceId,
    );
    await db.customStatement(
      'INSERT INTO liabilities '
      '(id, type, name, principal, interest_rate, currency, monthly_payment, '
      'owner_user_id, updated_at, updated_by_device, hlc, deleted_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      <Object?>[
        'liability-usd',
        'mortgage',
        'Cross-currency fixture',
        '1234567890.12345678',
        '0.0375',
        'USD',
        '98765.4321',
        'user-1',
        now,
        testDeviceId,
        hlc.toString(),
        null,
      ],
    );
  }

  Future<void> insertOptionsStrategyProfile(AppDatabase db) async {
    final now = DateTime.utc(2026, 1, 1).toIso8601String();
    const hlc = Hlc(
      wallMillis: 1700000000002,
      counter: 0,
      nodeId: testDeviceId,
    );
    await db.customStatement(
      'INSERT INTO options_strategy_profile '
      '(user_id, mode, allowed_strategies_json, min_dte, max_dte, '
      'delta_put_min, delta_put_max, delta_call_min, delta_call_max, '
      'max_capital_per_trade_pct, min_annualized_yield, min_open_interest, min_volume, '
      'max_bid_ask_spread_pct, avoid_earnings, avoid_macro_events, '
      'risk_disclosure_ack_at, '
      'owner_user_id, updated_at, updated_by_device, hlc, deleted_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        'user-1',
        'balanced',
        '["cash_secured_put","covered_call"]',
        21,
        45,
        '-0.30',
        '-0.15',
        '0.15',
        '0.30',
        '0.05',
        '0.12',
        100,
        10,
        '0.08',
        1,
        1,
        null,
        'user-1',
        now,
        testDeviceId,
        hlc.toString(),
        null,
      ],
    );
  }

  Future<void> insertKnowledgeNote(AppDatabase db) async {
    final now = DateTime.utc(2026, 1, 1).toIso8601String();
    const hlc = Hlc(
      wallMillis: 1700000000003,
      counter: 0,
      nodeId: testDeviceId,
    );
    await db.customStatement(
      'INSERT INTO knowledge_notes '
      '(id, title, body_md, created_at, owner_user_id, updated_at, '
      'updated_by_device, hlc) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      <Object?>[
        'note-1',
        'Domain backup',
        'Knowledge body',
        now,
        'user-1',
        now,
        testDeviceId,
        hlc.toString(),
      ],
    );
  }

  /// Count rows in a table.
  Future<int> countRows(AppDatabase db, String table) async {
    final row = await db
        .customSelect('SELECT COUNT(*) AS c FROM $table')
        .getSingle();
    return row.read<int>('c');
  }

  BackupService makeService(AppDatabase db) {
    return BackupService(
      db: db,
      codec: codec,
      outbox: DriftOutboxStore(db),
      deviceId: testDeviceId,
      stampHlc: () async => Hlc(
        wallMillis: DateTime.now().millisecondsSinceEpoch,
        counter: 0,
        nodeId: testDeviceId,
      ),
    );
  }

  Future<Uint8List> encryptPayload(
    AppDatabase db,
    Map<String, Object?> payload, {
    int? schemaVersion,
  }) async {
    final envelope = await codec.encrypt(
      passphrase: testPassphrase,
      plaintext: Uint8List.fromList(utf8.encode(jsonEncode(payload))),
      schemaVersion: schemaVersion ?? db.schemaVersion,
      iterations: testIterations,
    );
    return envelope.encodeBytes();
  }

  Future<Map<String, Object?>> decryptPayload(Uint8List bytes) async {
    final envelope = BackupEnvelope.decodeBytes(bytes);
    final plaintext = await codec.decrypt(
      passphrase: testPassphrase,
      envelope: envelope,
    );
    return jsonDecode(utf8.decode(plaintext)) as Map<String, Object?>;
  }

  group('BackupService', () {
    test(
      'export produces valid envelope that decrypts to correct JSON',
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
        expect(
          (header['tables'] as Map<String, Object?>).keys.toSet(),
          kBackupTables.toSet(),
        );

        // Verify data contains our rows.
        final data = json['data'] as Map<String, Object?>;
        expect(data.keys.toSet(), kBackupTables.toSet());
        final accounts = data['accounts'] as List<Object?>;
        expect(accounts.length, 1);
        expect((accounts[0] as Map)['id'], 'acct-1');
        expect((accounts[0] as Map)['name'], 'Test Account');

        final tags = data['tags'] as List<Object?>;
        expect(tags.length, 1);
        expect((tags[0] as Map)['id'], 'tag-1');
      },
    );

    test('domain archive restores only that OS', () async {
      final sourceDb = makeTestDatabase();
      addTearDown(sourceDb.close);
      await insertKnowledgeNote(sourceDb);
      await insertTestTag(sourceDb);

      service = makeService(sourceDb);
      final bytes = await service.exportBackup(
        passphrase: testPassphrase,
        overrideIterations: testIterations,
        domain: DomainScope.knowledge,
      );
      final envelope = BackupEnvelope.decodeBytes(bytes);
      final plaintext = await codec.decrypt(
        passphrase: testPassphrase,
        envelope: envelope,
      );
      final payload =
          jsonDecode(utf8.decode(plaintext)) as Map<String, Object?>;
      final header = payload['header'] as Map<String, Object?>;
      final data = payload['data'] as Map<String, Object?>;
      expect(header['domain'], 'knowledge');
      expect(data.keys, everyElement(startsWith('knowledge_')));
      expect(data.keys, isNot(contains('tags')));

      final targetDb = makeTestDatabase();
      addTearDown(targetDb.close);
      await insertTestTag(targetDb, id: 'existing-tag');
      final restoreService = makeService(targetDb);
      await expectLater(
        restoreService.restoreBackup(
          passphrase: testPassphrase,
          fileBytes: bytes,
          expectedDomain: DomainScope.finance,
        ),
        throwsA(isA<BackupValidationException>()),
      );
      expect(await countRows(targetDb, 'tags'), 1);

      final domainResult = await restoreService.restoreBackup(
        passphrase: testPassphrase,
        fileBytes: bytes,
        expectedDomain: DomainScope.knowledge,
      );

      expect(domainResult.archiveDomain, DomainScope.knowledge);
      expect(domainResult.archiveSchemaVersion, targetDb.schemaVersion);
      expect(domainResult.toDiagnosticJson()['domain'], 'knowledge');
      expect(await countRows(targetDb, 'knowledge_notes'), 1);
      expect(await countRows(targetDb, 'tags'), 1);
    });

    test(
      'generic export preserves currency and exact decimal machine values',
      () async {
        final sourceDb = makeTestDatabase();
        addTearDown(sourceDb.close);
        await insertTestLiability(sourceDb);

        final bytes = await makeService(sourceDb).exportBackup(
          passphrase: testPassphrase,
          overrideIterations: testIterations,
        );
        final envelope = BackupEnvelope.decodeBytes(bytes);
        final plaintext = await codec.decrypt(
          passphrase: testPassphrase,
          envelope: envelope,
        );
        final payload =
            jsonDecode(utf8.decode(plaintext)) as Map<String, Object?>;
        final data = payload['data'] as Map<String, Object?>;
        final liabilities = data['liabilities'] as List<Object?>;
        final exported = liabilities.single as Map<String, Object?>;

        expect(exported['currency'], 'USD');
        expect(exported['principal'], '1234567890.12345678');
        expect(exported['interest_rate'], '0.0375');
        expect(exported['monthly_payment'], '98765.4321');
        final principal = exported['principal'].toString();
        expect(principal, isNot(contains(r'$')));
        expect(principal, isNot(contains(',')));

        final targetDb = makeTestDatabase();
        addTearDown(targetDb.close);
        await makeService(
          targetDb,
        ).restoreBackup(passphrase: testPassphrase, fileBytes: bytes);
        final restored = await targetDb
            .customSelect(
              'SELECT principal, interest_rate, currency, monthly_payment '
              'FROM liabilities WHERE id = ?',
              variables: const <Variable<Object>>[
                Variable<String>('liability-usd'),
              ],
            )
            .getSingle();
        expect(restored.read<String>('currency'), 'USD');
        expect(restored.read<String>('principal'), '1234567890.12345678');
        expect(restored.read<String>('interest_rate'), '0.0375');
        expect(restored.read<String>('monthly_payment'), '98765.4321');
      },
    );

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
      expect(result.archiveSchemaVersion, targetDb.schemaVersion);
      expect(result.archiveDomain, isNull);
      expect(result.tableCount, kBackupTables.length);
      expect(result.totalRows, 3);
      expect(result.toDiagnosticJson(), <String, Object>{
        'schema_version': targetDb.schemaVersion,
        'domain': 'full',
        'table_count': kBackupTables.length,
        'row_count': 3,
      });
      final diagnosticJson = jsonEncode(result.toDiagnosticJson());
      expect(diagnosticJson, isNot(contains('accounts')));
      expect(diagnosticJson, isNot(contains('Source Account')));

      // Verify actual data.
      expect(await countRows(targetDb, 'accounts'), 2);
      expect(await countRows(targetDb, 'tags'), 1);
    });

    test('wrong passphrase throws BackupAuthenticationException', () async {
      final sourceDb = makeTestDatabase();
      addTearDown(sourceDb.close);
      await insertTestAccount(sourceDb);

      service = makeService(sourceDb);
      final bytes = await service.exportBackup(
        passphrase: testPassphrase,
        overrideIterations: testIterations,
      );

      final targetDb = makeTestDatabase();
      addTearDown(targetDb.close);
      await insertTestAccount(targetDb, id: 'preserved');
      final restoreService = makeService(targetDb);
      await expectLater(
        restoreService.restoreBackup(
          passphrase: 'wrong-passphrase',
          fileBytes: bytes,
        ),
        throwsA(isA<BackupAuthenticationException>()),
      );
      expect(await countRows(targetDb, 'accounts'), 1);
      final rows = await targetDb.customSelect('SELECT id FROM accounts').get();
      expect(rows.single.read<String>('id'), 'preserved');
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
      final rows = await targetDb.customSelect('SELECT id FROM accounts').get();
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

      // Verify dirty pointers were enqueued transactionally with the rows.
      final ops = await targetDb
          .customSelect('SELECT table_name, row_id FROM op_outbox')
          .get();
      expect(ops, hasLength(2)); // 1 account + 1 tag
      final tableNames = ops
          .map((row) => row.read<String>('table_name'))
          .toSet();
      expect(tableNames, containsAll(['accounts', 'tags']));
    });

    test(
      'restore enqueues singleton table pointers with registry primary keys',
      () async {
        final sourceDb = makeTestDatabase();
        addTearDown(sourceDb.close);
        await insertOptionsStrategyProfile(sourceDb);

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

        final rows = await targetDb
            .customSelect('SELECT user_id FROM options_strategy_profile')
            .get();
        expect(rows.single.read<String>('user_id'), 'user-1');

        final profileOps = await targetDb
            .customSelect(
              'SELECT row_id FROM op_outbox '
              'WHERE table_name = ?',
              variables: [Variable.withString('options_strategy_profile')],
            )
            .get();
        expect(profileOps, hasLength(1));
        expect(profileOps.single.read<String>('row_id'), 'user-1');
      },
    );

    test('truncated archive preserves the existing database', () async {
      final targetDb = makeTestDatabase();
      addTearDown(targetDb.close);
      await insertTestAccount(targetDb, id: 'preserved');

      final restoreService = makeService(targetDb);
      await expectLater(
        restoreService.restoreBackup(
          passphrase: testPassphrase,
          fileBytes: Uint8List.fromList(utf8.encode('{"magic":')),
        ),
        throwsA(isA<FormatException>()),
      );

      final rows = await targetDb.customSelect('SELECT id FROM accounts').get();
      expect(rows.single.read<String>('id'), 'preserved');
    });

    test('malformed authenticated payload preserves existing data', () async {
      final targetDb = makeTestDatabase();
      addTearDown(targetDb.close);
      await insertTestAccount(targetDb, id: 'preserved');
      final envelope = await codec.encrypt(
        passphrase: testPassphrase,
        plaintext: Uint8List.fromList(utf8.encode('{not-json')),
        schemaVersion: targetDb.schemaVersion,
        iterations: testIterations,
      );

      await expectLater(
        makeService(targetDb).restoreBackup(
          passphrase: testPassphrase,
          fileBytes: envelope.encodeBytes(),
        ),
        throwsA(isA<BackupValidationException>()),
      );
      final rows = await targetDb.customSelect('SELECT id FROM accounts').get();
      expect(rows.single.read<String>('id'), 'preserved');
    });

    test('incomplete current-schema archive is rejected before wipe', () async {
      final sourceDb = makeTestDatabase();
      addTearDown(sourceDb.close);
      await insertTestAccount(sourceDb);
      final exported = await makeService(sourceDb).exportBackup(
        passphrase: testPassphrase,
        overrideIterations: testIterations,
      );
      final payload = await decryptPayload(exported);
      final header = payload['header'] as Map<String, Object?>;
      final data = payload['data'] as Map<String, Object?>;
      (header['tables'] as Map<String, Object?>).remove('tags');
      data.remove('tags');
      final incomplete = await encryptPayload(sourceDb, payload);

      final targetDb = makeTestDatabase();
      addTearDown(targetDb.close);
      await insertTestAccount(targetDb, id: 'preserved');
      await expectLater(
        makeService(
          targetDb,
        ).restoreBackup(passphrase: testPassphrase, fileBytes: incomplete),
        throwsA(isA<BackupValidationException>()),
      );
      final rows = await targetDb.customSelect('SELECT id FROM accounts').get();
      expect(rows.single.read<String>('id'), 'preserved');
    });

    test(
      'older schema archive restores known rows without clearing sync metadata',
      () async {
        final sourceDb = makeTestDatabase();
        addTearDown(sourceDb.close);
        await insertTestAccount(sourceDb, id: 'legacy-account');
        final exported = await makeService(sourceDb).exportBackup(
          passphrase: testPassphrase,
          overrideIterations: testIterations,
        );
        final payload = await decryptPayload(exported);
        final header = payload['header'] as Map<String, Object?>;
        final data = payload['data'] as Map<String, Object?>;
        final accounts = data['accounts'];
        header
          ..['schemaVersion'] = sourceDb.schemaVersion - 1
          ..['tables'] = <String, Object?>{'accounts': 1};
        payload['data'] = <String, Object?>{'accounts': accounts};
        final legacyArchive = await encryptPayload(
          sourceDb,
          payload,
          schemaVersion: sourceDb.schemaVersion - 1,
        );

        final targetDb = makeTestDatabase();
        addTearDown(targetDb.close);
        await targetDb.customStatement(
          'INSERT INTO sync_meta(key, value) VALUES (?, ?)',
          <Object?>['sync.cursor', '42'],
        );
        final result = await makeService(
          targetDb,
        ).restoreBackup(passphrase: testPassphrase, fileBytes: legacyArchive);

        expect(result.tableCounts, <String, int>{'accounts': 1});
        final account = await targetDb
            .customSelect('SELECT id FROM accounts')
            .getSingle();
        expect(account.read<String>('id'), 'legacy-account');
        final cursor = await targetDb
            .customSelect(
              'SELECT value FROM sync_meta WHERE key = ?',
              variables: <Variable<Object>>[Variable.withString('sync.cursor')],
            )
            .getSingle();
        expect(cursor.read<String>('value'), '42');
      },
    );

    test(
      'restores a representative 1000-row archive within the test budget',
      () async {
        final sourceDb = makeTestDatabase();
        addTearDown(sourceDb.close);
        await sourceDb.transaction(() async {
          for (var i = 0; i < 1000; i++) {
            await insertTestAccount(
              sourceDb,
              id: 'account-$i',
              name: 'Account $i',
            );
          }
        });
        final bytes = await makeService(sourceDb).exportBackup(
          passphrase: testPassphrase,
          overrideIterations: testIterations,
        );

        final targetDb = makeTestDatabase();
        addTearDown(targetDb.close);
        final stopwatch = Stopwatch()..start();
        final result = await makeService(
          targetDb,
        ).restoreBackup(passphrase: testPassphrase, fileBytes: bytes);
        stopwatch.stop();

        expect(result.tableCounts['accounts'], 1000);
        expect(await countRows(targetDb, 'accounts'), 1000);
        expect(stopwatch.elapsed, lessThan(const Duration(seconds: 10)));
      },
    );

    test(
      'failed row insertion rolls data and outbox back atomically',
      () async {
        final sourceDb = makeTestDatabase();
        addTearDown(sourceDb.close);
        await insertTestAccount(sourceDb);
        final exported = await makeService(sourceDb).exportBackup(
          passphrase: testPassphrase,
          overrideIterations: testIterations,
        );
        final payload = await decryptPayload(exported);
        final header = payload['header'] as Map<String, Object?>;
        final data = payload['data'] as Map<String, Object?>;
        final accounts = data['accounts'] as List<Object?>;
        accounts.add(<String, Object?>{'id': 'invalid-row'});
        (header['tables'] as Map<String, Object?>)['accounts'] =
            accounts.length;
        final invalid = await encryptPayload(sourceDb, payload);

        final targetDb = makeTestDatabase();
        addTearDown(targetDb.close);
        await insertTestAccount(targetDb, id: 'preserved');
        final targetOutbox = DriftOutboxStore(targetDb);
        await targetOutbox.enqueue(table: 'accounts', rowId: 'preserved');

        var resumed = false;
        await expectLater(
          makeService(targetDb).restoreBackup(
            passphrase: testPassphrase,
            fileBytes: invalid,
            resumeSync: () => resumed = true,
          ),
          throwsA(anything),
        );
        expect(resumed, isTrue);
        final rows = await targetDb
            .customSelect('SELECT id FROM accounts')
            .get();
        expect(rows.single.read<String>('id'), 'preserved');
        final pointers = await targetDb
            .customSelect('SELECT table_name, row_id FROM op_outbox')
            .get();
        expect(pointers, hasLength(1));
        expect(pointers.single.read<String>('row_id'), 'preserved');
      },
    );

    test('soft-deleted rows (tombstones) are included in backup', () async {
      final sourceDb = makeTestDatabase();
      addTearDown(sourceDb.close);
      await insertTestAccount(sourceDb, id: 'acct-alive');
      // Insert tombstone using numeric timestamp (Drift stores DateTime as int).
      final deletedAtMs = DateTime.utc(2026, 6, 1).millisecondsSinceEpoch;
      final now = DateTime.utc(2026, 1, 1).toIso8601String();
      const hlc = Hlc(
        wallMillis: 1700000000002,
        counter: 0,
        nodeId: testDeviceId,
      );
      await sourceDb.customStatement(
        'INSERT INTO accounts '
        '(id, type, name, currency, owner_user_id, updated_at, updated_by_device, hlc, deleted_at, archived, category) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?)',
        [
          'acct-deleted',
          'cash',
          'Deleted Account',
          'CNY',
          'user-1',
          now,
          testDeviceId,
          hlc.toString(),
          deletedAtMs,
          'asset',
        ],
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
          .customSelect('SELECT id, deleted_at FROM accounts ORDER BY id')
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

    test(
      'resumeSync is NOT called when decryption fails before pause',
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
      },
    );
  });
}
