import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/contracts/context_evidence.dart';
import 'package:naviwealth/core/ai/contracts/memory_record.dart';
import 'package:naviwealth/core/ai/local/embedding/embedder.dart';
import 'package:naviwealth/core/ai/local/memory/event_store.dart';
import 'package:naviwealth/core/ai/local/memory/memory_runtime.dart';
import 'package:naviwealth/core/ai/local/memory/memory_store.dart';
import 'package:naviwealth/core/backup/backup_codec.dart';
import 'package:naviwealth/core/backup/backup_service.dart';
import 'package:naviwealth/core/config/app_config.dart';
import 'package:naviwealth/core/data_management/data_management.dart';
import 'package:naviwealth/core/logging/app_logger.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/sync_payload_store.dart';
import 'package:talker/talker.dart';

import '../persistence/test_database.dart';

const _owner = 'user-1';
const _passphrase = 'memory-recovery-fixture';
final _now = DateTime.utc(2026, 9, 30);

MemoryRecord _record(
  String id, {
  String owner = _owner,
  EvidenceAuthority authority = EvidenceAuthority.userConfirmed,
  String? supersedes,
  DateTime? validUntil,
}) => MemoryRecord(
  id: id,
  kind: MemoryKind.semantic,
  role: MemoryRole.guidance,
  authority: authority,
  ownerUserId: owner,
  source: 'user:confirmed',
  sourceId: id,
  title: 'Cash buffer',
  summary: 'Keep a twelve month cash buffer.',
  payload: const {'months': 12},
  entities: const {'cash'},
  importance: 0.9,
  confidence: 1,
  createdAt: _now.subtract(const Duration(days: 30)),
  updatedAt: _now.subtract(const Duration(days: 1)),
  validFrom: _now.subtract(const Duration(days: 30)),
  validUntil: validUntil,
  supersedesId: supersedes,
);

BackupService _service(AppDatabase db, {String owner = _owner}) =>
    BackupService(
      db: db,
      codec: BackupCodec(),
      outbox: DriftOutboxStore(db),
      ownerUserId: owner,
    );

Future<Uint8List> _export(AppDatabase db) =>
    _service(db)
        .exportBackup(passphrase: _passphrase, overrideIterations: 1000);

Future<Map<String, Object?>> _decode(Uint8List bytes) async {
  final plaintext = await BackupCodec().decrypt(
    passphrase: _passphrase,
    envelope: BackupEnvelope.decodeBytes(bytes),
  );
  return (jsonDecode(utf8.decode(plaintext)) as Map<String, dynamic>)
      .cast<String, Object?>();
}

Future<Uint8List> _encode(Map<String, Object?> payload, int schema) async {
  return (await BackupCodec().encrypt(
    passphrase: _passphrase,
    plaintext: Uint8List.fromList(utf8.encode(jsonEncode(payload))),
    schemaVersion: schema,
    iterations: 1000,
  )).encodeBytes();
}

void main() {
  setUpAll(
    () => AppLogger.bootstrap(
      AppLogger(
        environment: AppEnvironment.dev,
        talker: Talker(settings: TalkerSettings(useConsoleLogs: false)),
      ),
    ),
  );
  test(
    'encrypted recovery preserves confirmed lineage and rebuilds vectors',
    () async {
      final source = makeTestDatabase();
      final target = makeTestDatabase();
      addTearDown(source.close);
      addTearDown(target.close);
      final sourceStore = SqliteMemoryStore(db: source);
      final old = _record(
        'old',
        validUntil: _now.subtract(const Duration(days: 1)),
      );
      final current = _record('current', supersedes: 'old');
      for (final record in [
        old,
        current,
        _record('derived', authority: EvidenceAuthority.deterministicDerived),
        _record('other-owner', owner: 'user-2'),
      ]) {
        await sourceStore.writeMemory(
          record,
          vector: [1, 0],
          fingerprint: 'old-model',
        );
      }
      final bytes = await _export(source);
      final data = (await _decode(bytes))['data'] as Map<String, dynamic>;
      expect(
        (data['memories'] as List).map((row) => (row as Map)['id']),
        unorderedEquals(['old', 'current']),
      );
      expect(data, isNot(contains('memory_embeddings')));

      final targetStore = SqliteMemoryStore(db: target);
      await targetStore.writeMemoryWithoutVector(
        _record('keep-derived', authority: EvidenceAuthority.sourceFact),
      );
      await targetStore.writeMemoryWithoutVector(
        _record('keep-other', owner: 'user-2'),
      );
      await targetStore.writeMemory(
        _record('replace-me'),
        vector: [1, 0],
        fingerprint: 'obsolete',
      );
      await _service(target)
          .restoreBackup(passphrase: _passphrase, fileBytes: bytes);
      expect((await targetStore.readMemory('old'))!.toJson(), old.toJson());
      expect(
        (await targetStore.readMemory('current'))!.toJson(),
        current.toJson(),
      );
      expect(await targetStore.readMemory('replace-me'), isNull);
      expect(await targetStore.readMemory('keep-derived'), isNotNull);
      expect(await targetStore.readMemory('keep-other'), isNotNull);
      expect(await DriftOutboxStore(target).depth(), 0);
      expect(
        (await target.customSelect('SELECT * FROM memory_embeddings').get()),
        isEmpty,
      );

      final runtime = MemoryRuntime(
        embedder: StubEmbedder(),
        memoryStore: targetStore,
        eventStore: SqliteEventStore(db: target),
        clock: () => _now,
      );
      final hits = await runtime.recall(
        ownerUserId: _owner,
        queryText: '${current.title}\n${current.summary}',
        sourcePrefixes: {'user:'},
      );
      expect(hits.map((hit) => hit.record.id), ['current']);
      expect(hits.single.semanticSim, closeTo(1, 0.001));
      final rebuilt = (await targetStore.readMemory('current'))!;
      expect(rebuilt.authority, current.authority);
      expect(rebuilt.provenance.toJson(), current.provenance.toJson());
      expect(rebuilt.supersedesId, 'old');
      expect(rebuilt.updatedAt, current.updatedAt);
      expect(
        (await target
                .customSelect('SELECT memory_id FROM memory_embeddings')
                .get())
            .single
            .read<String>('memory_id'),
        'current',
      );
    },
  );

  test(
    'full backup isolates source rows and preserves other-owner dirty pointers',
    () async {
      final source = makeTestDatabase();
      final target = makeTestDatabase();
      addTearDown(source.close);
      addTearDown(target.close);
      Future<void> account(
        AppDatabase db,
        String id,
        String owner,
      ) => db.customStatement(
        'INSERT INTO accounts (id, type, name, currency, owner_user_id, '
        'updated_at, updated_by_device, hlc) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        [id, 'cash', id, 'CNY', owner, 1700000000, 'device', '1000:0:device'],
      );
      await account(source, 'incoming', _owner);
      await account(source, 'excluded', 'user-2');
      final bytes = await _export(source);
      final payload = await _decode(bytes);
      final data = payload['data'] as Map<String, dynamic>;
      expect((data['accounts'] as List).map((row) => (row as Map)['id']), [
        'incoming',
      ]);
      expect((payload['header'] as Map)['ownerUserId'], _owner);
      await account(target, 'replaced', _owner);
      await account(target, 'preserved', 'user-2');
      final outbox = DriftOutboxStore(target);
      for (final id in ['replaced', 'preserved']) {
        await outbox.enqueue(table: 'accounts', rowId: id);
      }
      final extras = SyncPayloadStore(target);
      await extras.writeExtras('accounts', 'replaced', _owner, {'future': 1});
      await extras.writeExtras('accounts', 'preserved', 'user-2', {
        'future': 2,
      });
      await _service(target)
          .restoreBackup(passphrase: _passphrase, fileBytes: bytes);
      expect(
        (await target.customSelect('SELECT id FROM accounts').get()).map(
          (row) => row.read<String>('id'),
        ),
        unorderedEquals(['incoming', 'preserved']),
      );
      expect(
        (await DriftPendingRows(target).pointers()).map((p) => p.rowId),
        unorderedEquals(['incoming', 'preserved']),
      );
      expect(await extras.extras('accounts', 'replaced', _owner), isEmpty);
      expect(await extras.extras('accounts', 'preserved', 'user-2'), {
        'future': 2,
      });
    },
  );

  test(
    'empty foreign-owner archive and unknown columns fail before pausing sync',
    () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final store = SqliteMemoryStore(db: db);
      await store.writeMemoryWithoutVector(_record('protected'));
      final empty = makeTestDatabase();
      addTearDown(empty.close);
      final foreignBytes = await _service(
        empty,
        owner: 'user-2',
      ).exportBackup(passphrase: _passphrase, overrideIterations: 1000);
      final invalidPayload = await _decode(await _export(db));
      final invalidData = invalidPayload['data'] as Map<String, dynamic>;
      ((invalidData['memories'] as List).single as Map)['unknown_column'] =
          'bad';
      final invalidBytes = await _encode(invalidPayload, db.schemaVersion);
      for (final bytes in [foreignBytes, invalidBytes]) {
        var paused = false;
        await expectLater(
          _service(db).restoreBackup(
            passphrase: _passphrase,
            fileBytes: bytes,
            pauseSync: () => paused = true,
          ),
          throwsA(isA<BackupValidationException>()),
        );
        expect(paused, isFalse);
        expect(await store.readMemory('protected'), isNotNull);
      }
    },
  );

  test(
    'shared cleanup preserves confirmed records and their vectors',
    () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final store = SqliteMemoryStore(db: db);
      await store.writeMemory(
        _record('confirmed'),
        vector: [1, 0],
        fingerprint: 'model',
      );
      await store.writeMemory(
        _record('derived', authority: EvidenceAuthority.modelDerived),
        vector: [1, 0],
        fingerprint: 'model',
      );
      await store.writeMemoryWithoutVector(
        _record(
          'other-derived',
          owner: 'user-2',
          authority: EvidenceAuthority.modelDerived,
        ),
      );
      final service = DataManagementService(
        database: db,
        ownerUserId: _owner,
        specs: const [],
      );
      expect((await service.inspectSharedData()).memoryRows, 1);
      expect(await service.clearSharedHistory(), 1);
      expect((await service.inspectSharedData()).historyRows, 0);
      expect(await store.readMemory('confirmed'), isNotNull);
      expect(await store.readMemory('derived'), isNull);
      expect(await store.readMemory('other-derived'), isNotNull);
      expect(
        (await db.customSelect('SELECT memory_id FROM memory_embeddings').get())
            .single
            .read<String>('memory_id'),
        'confirmed',
      );
    },
  );

  test(
    'v95 archive without memories preserves existing confirmed data',
    () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final store = SqliteMemoryStore(db: db);
      final confirmed = _record('preserved');
      await store.writeMemoryWithoutVector(confirmed);
      final payload = await _decode(await _export(db));
      final header = payload['header'] as Map<String, dynamic>;
      header['schemaVersion'] = 95;
      (header['tables'] as Map).remove('memories');
      (payload['data'] as Map).remove('memories');
      await _service(db).restoreBackup(
        passphrase: _passphrase,
        fileBytes: await _encode(payload, 95),
      );
      expect(
        (await store.readMemory('preserved'))!.toJson(),
        confirmed.toJson(),
      );
    },
  );

  test('foreign-owner or derived memory archive is rejected before destructive work', () async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final store = SqliteMemoryStore(db: db);
    await store.writeMemoryWithoutVector(_record('preserved'));
    final original = await _decode(await _export(db));
    for (final field in ['owner_user_id', 'authority']) {
      final payload = (jsonDecode(jsonEncode(original)) as Map<String, dynamic>)
          .cast<String, Object?>();
      final row = ((payload['data'] as Map)['memories'] as List).single as Map;
      row[field] = field == 'owner_user_id' ? 'user-2' : 'model_derived';
      var paused = false;
      await expectLater(
        _service(db).restoreBackup(
          passphrase: _passphrase,
          fileBytes: await _encode(payload, db.schemaVersion),
          pauseSync: () => paused = true,
        ),
        throwsA(isA<BackupValidationException>()),
      );
      expect(paused, isFalse);
      expect(await store.readMemory('preserved'), isNotNull);
    }
  });

  test(
    'insert collision rolls back confirmed replacement and dirty pointers',
    () async {
      final source = makeTestDatabase();
      final target = makeTestDatabase();
      addTearDown(source.close);
      addTearDown(target.close);
      await SqliteMemoryStore(db: source)
          .writeMemoryWithoutVector(_record('collision'));
      final store = SqliteMemoryStore(db: target);
      await store.writeMemoryWithoutVector(_record('preserved'));
      await store.writeMemoryWithoutVector(
        _record('collision', owner: 'user-2'),
      );
      await DriftOutboxStore(target).enqueue(table: 'accounts', rowId: 'dirty');
      await expectLater(
        _service(target).restoreBackup(
          passphrase: _passphrase,
          fileBytes: await _export(source),
        ),
        throwsA(anything),
      );
      expect(await store.readMemory('preserved'), isNotNull);
      expect((await store.readMemory('collision'))!.ownerUserId, 'user-2');
      expect(await DriftOutboxStore(target).depth(), 1);
    },
  );

  test('vector rebuilding cannot overwrite a concurrent edit or revive a deleted record', () async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final store = SqliteMemoryStore(db: db);
    final old = _record('edited');
    await store.writeMemoryWithoutVector(old);
    await store.writeMemoryWithoutVector(
      old.copyWith(summary: 'Changed by user', updatedAt: _now),
    );
    expect(
      await store.writeEmbeddingIfUnchanged(
        old,
        vector: [1, 0],
        fingerprint: 'model',
      ),
      isFalse,
    );
    expect((await store.readMemory('edited'))!.summary, 'Changed by user');
    await store.deleteMemory('edited');
    expect(
      await store.writeEmbeddingIfUnchanged(
        old,
        vector: [1, 0],
        fingerprint: 'model',
      ),
      isFalse,
    );
    expect(await store.readMemory('edited'), isNull);
  });
}
