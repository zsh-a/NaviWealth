import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/knowledge/data/knowledge_repository.dart';
import 'package:naviwealth/features/knowledge/domain/knowledge_models.dart';

import '../../../core/persistence/test_database.dart';
import '../../../core/sync/_outbox_test_ext.dart';

void main() {
  late AppDatabase db;
  late InMemoryOutboxStore outbox;
  late KnowledgeRepository repo;

  const owner = 'u-test';
  final created = DateTime.utc(2026, 1, 1);

  setUp(() {
    db = makeTestDatabase();
    outbox = InMemoryOutboxStore();
    repo = KnowledgeRepository(db: db, outbox: outbox);
  });

  tearDown(() async => db.close());

  SyncMeta meta(DateTime at) => SyncMeta(
    ownerUserId: owner,
    updatedAt: at,
    updatedByDevice: 'dev-test',
    hlc: Hlc.zero('dev-test'),
  );

  // Distinct timestamp per stamp so each touched row gets its own meta,
  // mirroring how `mutationStamperProvider.stamp()` is wired in the UI.
  var stampCounter = 0;
  Future<SyncMeta> stamp() async {
    stampCounter++;
    return meta(created.add(Duration(seconds: stampCounter)));
  }

  KnowledgeNote note({
    required String id,
    required String title,
    String body = '',
    List<String> tags = const <String>[],
  }) => KnowledgeNote(
    id: id,
    title: title,
    bodyMd: body,
    tags: tags,
    createdAt: created,
    sync: meta(created),
  );

  KnowledgeConcept concept({
    required String id,
    required String name,
    List<String> aliases = const <String>[],
    String summary = '',
    List<String> related = const <String>[],
  }) => KnowledgeConcept(
    id: id,
    name: name,
    aliases: aliases,
    summaryMd: summary,
    relatedConceptIds: related,
    createdAt: created,
    sync: meta(created),
  );

  group('mergeNotes', () {
    test('unions tags, tombstones duplicate, stamps mergedIntoId', () async {
      await repo.upsertNote(
        note(id: 'keep', title: '港卡续期', tags: const ['finance', 'hk']),
      );
      await repo.upsertNote(
        note(id: 'dup', title: '香港卡要续', tags: const ['hk', 'reminder']),
      );
      outbox.clearQueued();

      final primary = (await repo.findNote(ownerUserId: owner, id: 'keep'))!;
      final dup = (await repo.findNote(ownerUserId: owner, id: 'dup'))!;
      final survivor = await repo.mergeNotes(
        primary: primary,
        duplicates: [dup],
        stamp: stamp,
      );

      // Survivor keeps id + title, unions tags.
      expect(survivor.id, 'keep');
      expect(survivor.title, '港卡续期');
      expect(survivor.tags.toSet(), {'finance', 'hk', 'reminder'});

      // Duplicate is soft-deleted and points at the survivor.
      final dupAfter = await repo.findNote(ownerUserId: owner, id: 'dup');
      expect(dupAfter!.sync.deletedAt, isNotNull);
      expect(dupAfter.mergedIntoId, 'keep');

      // Live list shows only the survivor.
      final live = await repo.listNotes(ownerUserId: owner);
      expect(live.map((n) => n.id), <String>['keep']);

      // Both touched rows enqueued for sync.
      expect(outbox.queued.map((e) => e.rowId).toSet(), {'keep', 'dup'});
    });

    test('merged_title / merged_body override the survivor fields', () async {
      await repo.upsertNote(note(id: 'a', title: 'old', body: 'old body'));
      await repo.upsertNote(note(id: 'b', title: 'dup', body: 'dup body'));

      final survivor = await repo.mergeNotes(
        primary: (await repo.findNote(ownerUserId: owner, id: 'a'))!,
        duplicates: [(await repo.findNote(ownerUserId: owner, id: 'b'))!],
        stamp: stamp,
        mergedTitle: '合并后的标题',
        mergedBody: '合并后的正文',
      );

      expect(survivor.title, '合并后的标题');
      expect(survivor.bodyMd, '合并后的正文');
      final reloaded = await repo.findNote(ownerUserId: owner, id: 'a');
      expect(reloaded!.title, '合并后的标题');
    });

    test('a duplicate_id equal to primary is ignored', () async {
      await repo.upsertNote(note(id: 'a', title: 'x', tags: const ['t']));
      final p = (await repo.findNote(ownerUserId: owner, id: 'a'))!;
      await repo.mergeNotes(primary: p, duplicates: [p], stamp: stamp);
      final after = await repo.findNote(ownerUserId: owner, id: 'a');
      expect(after!.sync.deletedAt, isNull, reason: 'primary must survive');
    });
  });

  group('mergeConcepts', () {
    test('folds duplicate name into aliases + unions related', () async {
      await repo.upsertConcept(
        concept(
          id: 'keep',
          name: 'FIRE',
          aliases: const ['fi'],
          related: const ['x'],
        ),
      );
      await repo.upsertConcept(
        concept(
          id: 'dup',
          name: '财务自由',
          aliases: const ['retire'],
          related: const ['y'],
        ),
      );

      final survivor = await repo.mergeConcepts(
        primary: (await repo.findConcept(ownerUserId: owner, id: 'keep'))!,
        duplicates: [(await repo.findConcept(ownerUserId: owner, id: 'dup'))!],
        stamp: stamp,
      );

      expect(survivor.name, 'FIRE');
      // Duplicate's name becomes an alias so the old name still resolves.
      expect(survivor.aliases.toSet(), {'fi', 'retire', '财务自由'});
      expect(survivor.relatedConceptIds.toSet(), {'x', 'y'});

      final dupAfter = await repo.findConcept(ownerUserId: owner, id: 'dup');
      expect(dupAfter!.sync.deletedAt, isNotNull);
      expect(dupAfter.mergedIntoId, 'keep');
    });

    test('re-points inbound related links from duplicate to primary', () async {
      await repo.upsertConcept(concept(id: 'keep', name: 'A'));
      await repo.upsertConcept(concept(id: 'dup', name: 'A-prime'));
      // A third concept links to the duplicate.
      await repo.upsertConcept(
        concept(id: 'other', name: 'C', related: const ['dup']),
      );

      await repo.mergeConcepts(
        primary: (await repo.findConcept(ownerUserId: owner, id: 'keep'))!,
        duplicates: [(await repo.findConcept(ownerUserId: owner, id: 'dup'))!],
        stamp: stamp,
      );

      final other = await repo.findConcept(ownerUserId: owner, id: 'other');
      expect(other!.relatedConceptIds, <String>[
        'keep',
      ], reason: 'inbound link should follow the merge');
    });
  });
}
