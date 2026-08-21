import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/knowledge/application/knowledge_deletion_service.dart';
import 'package:naviwealth/features/knowledge/data/knowledge_repository.dart';
import 'package:naviwealth/features/knowledge/domain/knowledge_models.dart';

import '../../../core/persistence/test_database.dart';
import '../../finance/data/repositories/_stub_stamper.dart';

final _created = DateTime.utc(2026, 8, 21);

SyncMeta _meta() => SyncMeta(
  ownerUserId: 'user',
  updatedAt: _created,
  updatedByDevice: 'device',
  hlc: Hlc.zero('device'),
);

void main() {
  test('delete tombstones relations and guarded undo restores them', () async {
    final AppDatabase db = makeTestDatabase();
    addTearDown(db.close);
    final repository = KnowledgeRepository(
      db: db,
      outbox: InMemoryOutboxStore(),
    );
    final service = KnowledgeDeletionService(
      repository: repository,
      stamper: makeStubStamper(userId: 'user', deviceId: 'device'),
    );
    final note = KnowledgeNote(
      id: 'note',
      title: 'Source note',
      bodyMd: '![scan](attachment://scan-1)',
      tags: const <String>[],
      createdAt: _created,
      sync: _meta(),
    );
    final concept = KnowledgeConcept(
      id: 'concept',
      name: 'Optionality',
      aliases: const <String>[],
      summaryMd: '',
      relatedConceptIds: const <String>[],
      createdAt: _created,
      sync: _meta(),
    );
    await repository.upsertNote(note);
    await repository.upsertConcept(concept);
    final relation = KnowledgeRelation(
      id: knowledgeRelationId(
        fromKind: 'note',
        fromId: note.id,
        relation: KnowledgeRelationType.relatedTo,
        toKind: 'concept',
        toId: concept.id,
      ),
      fromKind: 'note',
      fromId: note.id,
      relation: KnowledgeRelationType.relatedTo,
      toKind: 'concept',
      toId: concept.id,
      createdAt: _created,
      sync: _meta(),
    );
    await repository.upsertRelation(relation);

    final impact = await service.analyze(
      ownerUserId: 'user',
      kind: KnowledgeEntryKind.note,
      id: note.id,
    );
    expect(impact.relationCount, 1);
    expect(impact.attachmentCount, 1);

    final change = await service.delete(
      ownerUserId: 'user',
      kind: KnowledgeEntryKind.note,
      id: note.id,
    );
    expect(
      (await repository.findNote(
        ownerUserId: 'user',
        id: note.id,
      ))?.sync.deletedAt,
      isNotNull,
    );
    expect(
      await repository.listRelationsForObject(
        ownerUserId: 'user',
        kind: 'note',
        id: note.id,
      ),
      isEmpty,
    );

    expect(await change?.undo(), isTrue);
    expect(
      (await repository.findNote(
        ownerUserId: 'user',
        id: note.id,
      ))?.sync.deletedAt,
      isNull,
    );
    expect(
      await repository.listRelationsForObject(
        ownerUserId: 'user',
        kind: 'note',
        id: note.id,
      ),
      hasLength(1),
    );
  });
}
