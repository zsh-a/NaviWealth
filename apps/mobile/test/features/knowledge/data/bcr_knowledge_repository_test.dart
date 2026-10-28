import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/auth/domain_scope.dart';
import 'package:naviwealth/core/data_management/data_management.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/persistence/owner_data_migration.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/core/sync/sync_table_registry.dart';
import 'package:naviwealth/features/knowledge/data/bcr_knowledge_repository.dart';
import 'package:naviwealth/features/knowledge/data/knowledge_repository.dart';
import 'package:naviwealth/features/knowledge/data_management/knowledge_data_management.dart';
import 'package:naviwealth/features/knowledge/domain/bcr_knowledge_source.dart';
import 'package:naviwealth/features/knowledge/domain/knowledge_models.dart';

import '../../../core/persistence/test_database.dart';
import '../../finance/data/repositories/_stub_stamper.dart';
import '../bcr_test_fixture.dart';

void main() {
  late AppDatabase db;
  late BcrKnowledgeRepository repository;
  final url = normalizeBcrLibraryUrl(
    'https://notes.example.com/notes/knowledge',
  );
  final sourceId = bcrSourceId(url);

  setUp(() {
    db = makeTestDatabase();
    repository = BcrKnowledgeRepository(db);
  });
  tearDown(() => db.close());

  Future<void> import({
    String owner = 'owner',
    String? expected,
    String body = 'Equity allocation stays below 60%.',
    int count = 1,
    Uri? libraryUrl,
  }) async => repository.importArchive(
    owner: owner,
    label: 'Research',
    libraryUrl: libraryUrl ?? url,
    archive: makeBcrArchive(body: body, count: count),
    expectedCacheRevision: expected,
    importToken: await repository.beginImport(
      owner: owner,
      libraryUrl: libraryUrl ?? url,
    ),
  );

  test(
    'reimport keeps identity, replaces removed notes and never queues sync',
    () async {
      await import(count: 2);
      final first = (await repository.listSources('owner')).single;
      expect(first.notes, hasLength(2));
      final before = first.notes.last.fingerprint;
      await import(expected: first.cacheRevision, body: 'New policy');
      final source = (await repository.listSources('owner')).single;
      expect(source.id, first.id);
      expect(source.notes.single.body, 'New policy');
      expect(source.notes.single.fingerprint, isNot(before));
      expect(source.cacheRevision, isNot(first.cacheRevision));
      expect(await db.select(db.knowledgeNotes).get(), isEmpty);
      expect(await db.customSelect('SELECT * FROM op_outbox').get(), isEmpty);
      expect(
        kSyncTableRegistrations.map((row) => row.table),
        isNot(contains('knowledge_source_cache')),
      );
    },
  );

  test('owners and libraries cannot read or replace each other', () async {
    await import();
    await import(owner: 'other', body: 'Private other material');
    await import(
      libraryUrl: normalizeBcrLibraryUrl(
        'https://second.example.com/knowledge',
      ),
      body: 'Second library',
    );
    expect(await repository.listSources('owner'), hasLength(2));
    expect(
      (await repository.listSources('other')).single.notes.single.body,
      'Private other material',
    );
    await expectLater(
      import(
        owner: 'other',
        expected: (await repository.findSource(
          'owner',
          sourceId,
        ))!.cacheRevision,
      ),
      throwsA(BcrKnowledgeCacheFailure.changed),
    );
  });

  test(
    'reset invalidates a first-import preview with no previous source',
    () async {
      final token = await repository.beginImport(
        owner: 'owner',
        libraryUrl: url,
      );
      final service = DataManagementService(
        database: db,
        ownerUserId: 'owner',
        specs: [knowledgeDataManagementSpec],
      );
      await service.resetLocalDomain(DomainScope.knowledge);
      await expectLater(
        repository.importArchive(
          owner: 'owner',
          label: 'Research',
          libraryUrl: url,
          archive: makeBcrArchive(),
          expectedCacheRevision: null,
          importToken: token,
        ),
        throwsA(BcrKnowledgeCacheFailure.changed),
      );
      expect(await repository.listSources('owner'), isEmpty);
    },
  );

  test(
    'Unicode evidence and paging preserve complete surrogate pairs',
    () async {
      final body = '${'a' * 201}😀${'b' * 199}needle';
      await import(body: body);
      final source = (await repository.listSources('owner')).single;
      final ref = BcrKnowledgeReference.fromHit(
        BcrKnowledgeHit(source: source, note: source.notes.single),
        query: 'needle',
      );
      expect(ref.excerpt, contains('😀'));
      final long = '${'a' * 11999}😀尾';
      final first = bcrTextPage(long, 0);
      final second = bcrTextPage(long, first.nextOffset!);
      expect(first.text + second.text, long);
      expect(second.text, '😀尾');
      expect(second.nextOffset, isNull);
    },
  );

  test(
    'stale preview and failed writes retain the complete prior snapshot',
    () async {
      await import();
      final old = (await repository.listSources('owner')).single;
      await import(expected: old.cacheRevision, body: 'Latest');
      await expectLater(
        import(expected: old.cacheRevision, body: 'Stale'),
        throwsA(BcrKnowledgeCacheFailure.changed),
      );
      final latest = (await repository.listSources('owner')).single;
      await db.customStatement(
        "CREATE TRIGGER reject_bcr_write BEFORE UPDATE ON knowledge_source_cache BEGIN SELECT RAISE(ABORT, 'disk failure'); END",
      );
      await expectLater(
        import(expected: latest.cacheRevision, body: 'Failed'),
        throwsA(anything),
      );
      expect(
        (await repository.listSources('owner')).single.notes.single.body,
        'Latest',
      );
    },
  );

  test(
    'clear cache and reset notify existing readers and isolate owners',
    () async {
      for (final reset in [false, true]) {
        await import();
        if ((await repository.listSources('other')).isEmpty) {
          await import(owner: 'other');
        }
        final events = StreamIterator(repository.watchSources('owner'));
        expect(await events.moveNext(), isTrue);
        expect(events.current, hasLength(1));
        final service = DataManagementService(
          database: db,
          ownerUserId: 'owner',
          specs: [knowledgeDataManagementSpec],
        );
        if (reset) {
          await service.resetLocalDomain(DomainScope.knowledge);
        } else {
          await service.clearCache(DomainScope.knowledge);
        }
        expect(
          await events.moveNext().timeout(const Duration(seconds: 3)),
          isTrue,
        );
        expect(events.current, isEmpty);
        expect(await repository.listSources('other'), hasLength(1));
        await events.cancel();
      }
    },
  );

  test(
    'source refresh and cache removal preserve saved decision evidence',
    () async {
      await import();
      final source = (await repository.listSources('owner')).single;
      final snapshot = BcrKnowledgeReference.fromHit(
        BcrKnowledgeHit(source: source, note: source.notes.single),
      ).toMarkdown();
      final outbox = InMemoryOutboxStore();
      final decisions = KnowledgeRepository(db: db, outbox: outbox);
      final stamp = await makeStubStamper(userId: 'owner').stamp();
      final decision = KnowledgeDecision(
        id: 'decision',
        question: 'Raise allocation?',
        options: [DecisionOption(label: 'Keep')],
        selectedLabel: 'Keep',
        status: DecisionStatus.active,
        rationaleMd: snapshot,
        decidedAt: stamp.now,
        sync: SyncMeta(
          ownerUserId: stamp.ownerUserId,
          updatedAt: stamp.now,
          updatedByDevice: stamp.deviceId,
          hlc: stamp.hlc,
        ),
      );
      await decisions.upsertDecision(decision);
      await import(expected: source.cacheRevision, body: 'Changed to 90%.');
      final current = (await repository.listSources('owner')).single;
      await repository.removeSource(
        owner: 'owner',
        id: current.id,
        expectedCacheRevision: current.cacheRevision,
      );
      final saved = await decisions.findDecision(
        ownerUserId: 'owner',
        id: 'decision',
      );
      expect(saved!.rationaleMd, snapshot);
      expect(saved.rationaleMd, contains('60%'));
      expect(saved.rationaleMd, contains(source.notes.single.fingerprint));
    },
  );

  test(
    'search reaches old notes beyond the Memory subscription window',
    () async {
      await import(count: 300);
      final source = (await repository.listSources('owner')).single;
      final result = searchBcrKnowledge([source], 'Equity allocation');
      expect(result.single.note.id, 'note-299');
    },
  );

  test('library URL identities are independent of name and trailing slash', () {
    expect(bcrSourceId(normalizeBcrLibraryUrl('${url.toString()}/')), sourceId);
    for (final value in [
      'javascript:alert(1)',
      'https://user:password@example.com/knowledge',
      'https://example.com/knowledge?note=one',
      'https://example.com/#fragment',
    ]) {
      expect(() => normalizeBcrLibraryUrl(value), throwsFormatException);
    }
  });

  test(
    'owner transfer preserves the offline source and its content identity',
    () async {
      await import();
      await OwnerDataMigration(db).transfer(from: 'owner', to: 'signed-in');
      expect(await repository.listSources('owner'), isEmpty);
      expect((await repository.listSources('signed-in')).single.id, sourceId);
    },
  );

  test('cached text survives closing and reopening the database', () async {
    final directory = await Directory.systemTemp.createTemp('bcr-cache-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/cache.db');
    final first = AppDatabase(NativeDatabase(file));
    final firstRepository = BcrKnowledgeRepository(first);
    await firstRepository.importArchive(
      owner: 'owner',
      label: 'Research',
      libraryUrl: url,
      archive: makeBcrArchive(),
      expectedCacheRevision: null,
      importToken: await firstRepository.beginImport(
        owner: 'owner',
        libraryUrl: url,
      ),
    );
    await first.close();
    final reopened = AppDatabase(NativeDatabase(file));
    try {
      expect(
        (await BcrKnowledgeRepository(reopened).listSources('owner'))
            .single
            .notes
            .single
            .body,
        contains('60%'),
      );
    } finally {
      await reopened.close();
    }
  });
}
