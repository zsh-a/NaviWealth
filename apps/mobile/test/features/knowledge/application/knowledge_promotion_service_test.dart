import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/knowledge/application/knowledge_promotion_service.dart';
import 'package:naviwealth/features/knowledge/data/capture_kind.dart';
import 'package:naviwealth/features/knowledge/data/knowledge_repository.dart';
import 'package:naviwealth/features/knowledge/domain/knowledge_models.dart';

import '../../../core/persistence/test_database.dart';

void main() {
  const owner = 'promotion-owner';
  final createdAt = DateTime.utc(2026, 7, 21);
  late AppDatabase db;
  late KnowledgeRepository repository;
  late KnowledgePromotionService service;
  var stampCounter = 0;

  setUp(() {
    stampCounter = 0;
    db = makeTestDatabase();
    repository = KnowledgeRepository(db: db, outbox: InMemoryOutboxStore());
    service = KnowledgePromotionService(
      repository: repository,
      ownerUserId: owner,
      stamp: () async {
        stampCounter++;
        return SyncMeta(
          ownerUserId: owner,
          updatedAt: createdAt.add(Duration(seconds: stampCounter)),
          updatedByDevice: 'device',
          hlc: Hlc.zero('device'),
        );
      },
    );
  });

  tearDown(() => db.close());

  KnowledgeNote note(String id) => KnowledgeNote(
    id: id,
    title: 'Title $id',
    bodyMd: 'Body $id',
    tags: const <String>[],
    createdAt: createdAt,
    sync: SyncMeta(
      ownerUserId: owner,
      updatedAt: createdAt,
      updatedByDevice: 'device',
      hlc: Hlc.zero('device'),
    ),
  );

  test('all structured capture kinds create their typed object', () async {
    const cases = <CaptureKind, KnowledgeEntryKind>{
      CaptureKind.decision: KnowledgeEntryKind.decision,
      CaptureKind.principle: KnowledgeEntryKind.principle,
      CaptureKind.assumption: KnowledgeEntryKind.assumption,
      CaptureKind.concept: KnowledgeEntryKind.concept,
      CaptureKind.experiment: KnowledgeEntryKind.experiment,
      CaptureKind.routine: KnowledgeEntryKind.routine,
    };

    for (final entry in cases.entries) {
      final source = note(entry.key.name);
      await repository.upsertNote(source);
      final result = await service.promoteCapture(
        note: source,
        kind: entry.key,
        scope: 'test/scope',
      );

      expect(result.kind, entry.value);
      expect(result.id, knowledgePromotionTargetId(entry.value, source.id));
      final promoted = await repository.findNote(
        ownerUserId: owner,
        id: source.id,
      );
      expect(promoted!.promotedToKind, entry.value.name);
      expect(promoted.promotedToId, result.id);
      expect(promoted.promotedAt, isNotNull);
      await _expectTypedObject(repository, result);
    }

    expect(await repository.listNotes(ownerUserId: owner), isEmpty);
  });

  test('promotion is idempotent and rejects a different target kind', () async {
    final source = note('same');
    await repository.upsertNote(source);

    final first = await service.promoteToDecision(source);
    final second = await service.promoteToDecision(source);
    expect(second.id, first.id);
    expect(() => service.promoteToConcept(source), throwsStateError);
  });

  test(
    'promotion redirects existing Note relations to the typed object',
    () async {
      final source = note('linked');
      await repository.upsertNote(source);
      final relationSync = await service.stamp();
      await repository.upsertRelation(
        KnowledgeRelation(
          id: knowledgeRelationId(
            fromKind: KnowledgeEntryKind.note.name,
            fromId: source.id,
            relation: KnowledgeRelationType.relatedTo,
            toKind: KnowledgeEntryKind.decision.name,
            toId: 'decision-1',
          ),
          fromKind: KnowledgeEntryKind.note.name,
          fromId: source.id,
          relation: KnowledgeRelationType.relatedTo,
          toKind: KnowledgeEntryKind.decision.name,
          toId: 'decision-1',
          createdAt: relationSync.updatedAt,
          sync: relationSync,
        ),
      );

      final promoted = await service.promoteToConcept(source);

      expect(
        await repository.listRelationsFrom(
          ownerUserId: owner,
          fromKind: KnowledgeEntryKind.note.name,
          fromId: source.id,
        ),
        isEmpty,
      );
      final redirected = await repository.listRelationsFrom(
        ownerUserId: owner,
        fromKind: KnowledgeEntryKind.concept.name,
        fromId: promoted.id,
      );
      expect(redirected, hasLength(1));
      expect(redirected.single.toId, 'decision-1');
    },
  );
}

Future<void> _expectTypedObject(
  KnowledgeRepository repository,
  KnowledgePromotionResult result,
) async {
  const owner = 'promotion-owner';
  final exists = switch (result.kind) {
    KnowledgeEntryKind.decision =>
      await repository.findDecision(ownerUserId: owner, id: result.id) != null,
    KnowledgeEntryKind.principle =>
      await repository.findPrinciple(ownerUserId: owner, id: result.id) != null,
    KnowledgeEntryKind.assumption =>
      await repository.findAssumption(ownerUserId: owner, id: result.id) !=
          null,
    KnowledgeEntryKind.concept =>
      await repository.findConcept(ownerUserId: owner, id: result.id) != null,
    KnowledgeEntryKind.experiment =>
      await repository.findExperiment(ownerUserId: owner, id: result.id) !=
          null,
    KnowledgeEntryKind.routine =>
      await repository.findRoutine(ownerUserId: owner, id: result.id) != null,
    KnowledgeEntryKind.note => false,
  };
  expect(exists, isTrue);
}
