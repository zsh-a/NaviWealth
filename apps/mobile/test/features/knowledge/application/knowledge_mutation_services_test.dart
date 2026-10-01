import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/knowledge/application/knowledge_decision_review_service.dart';
import 'package:naviwealth/features/knowledge/application/knowledge_edit_service.dart';
import 'package:naviwealth/features/knowledge/application/knowledge_relation_service.dart';
import 'package:naviwealth/features/knowledge/data/knowledge_repository.dart';
import 'package:naviwealth/features/knowledge/domain/knowledge_models.dart';

import '../../../core/persistence/test_database.dart';
import '../../finance/data/repositories/_stub_stamper.dart';

const _owner = 'knowledge-mutation-user';

void main() {
  late AppDatabase database;
  late InMemoryOutboxStore outbox;
  late KnowledgeRepository repository;
  late KnowledgeEditService editor;
  late KnowledgeDecisionReviewService reviewer;
  late KnowledgeRelationService relations;

  setUp(() {
    database = makeTestDatabase();
    outbox = InMemoryOutboxStore();
    repository = KnowledgeRepository(db: database, outbox: outbox);
    final stamper = makeStubStamper(userId: _owner);
    editor = KnowledgeEditService(repository: repository, stamper: stamper);
    reviewer = KnowledgeDecisionReviewService(
      repository: repository,
      stamper: stamper,
    );
    relations = KnowledgeRelationService(
      repository: repository,
      stamper: stamper,
    );
  });
  tearDown(() => database.close());

  test('stale Note and Decision saves retain newer canonical rows without enqueuing', () async {
    final note = _note('note', 1);
    final decision = _decision(1);
    await repository.upsertNote(note);
    await repository.upsertDecision(decision);
    await repository.upsertNote(_note('note', 2, title: 'Newer note'));
    await repository.upsertDecision(_decision(2, question: 'Newer decision'));
    final depth = await outbox.depth();
    await expectLater(
      editor.saveNote(draft: note, expectedHlc: note.sync.hlc),
      throwsA(KnowledgeEditFailure.changed),
    );
    await expectLater(
      editor.saveDecision(draft: decision, expectedHlc: decision.sync.hlc),
      throwsA(KnowledgeEditFailure.changed),
    );
    expect(
      (await repository.findNote(ownerUserId: _owner, id: note.id))!.title,
      'Newer note',
    );
    expect(
      (await repository.findDecision(
        ownerUserId: _owner,
        id: decision.id,
      ))!.question,
      'Newer decision',
    );
    expect(await outbox.depth(), depth);
  });

  test('deleted sources cannot be revived by an editor save', () async {
    final note = _note('note', 1);
    final decision = _decision(1);
    await repository.upsertNote(note);
    await repository.upsertDecision(decision);
    await repository.deleteEntry(
      kind: KnowledgeEntryKind.note,
      id: note.id,
      sync: _sync(2),
    );
    await repository.deleteEntry(
      kind: KnowledgeEntryKind.decision,
      id: decision.id,
      sync: _sync(3),
    );
    final depth = await outbox.depth();
    await expectLater(
      editor.saveNote(draft: note, expectedHlc: note.sync.hlc),
      throwsA(KnowledgeEditFailure.missing),
    );
    await expectLater(
      editor.saveDecision(draft: decision, expectedHlc: decision.sync.hlc),
      throwsA(KnowledgeEditFailure.missing),
    );
    expect(
      (await repository.findNote(
        ownerUserId: _owner,
        id: note.id,
      ))!.sync.deletedAt,
      isNotNull,
    );
    expect(
      (await repository.findDecision(
        ownerUserId: _owner,
        id: decision.id,
      ))!.sync.deletedAt,
      isNotNull,
    );
    expect(await outbox.depth(), depth);
  });

  test('editor lookup is scoped to the current owner', () async {
    final foreign = _note('foreign', 1, owner: 'another-owner');
    await repository.upsertNote(foreign);
    await expectLater(
      editor.saveNote(draft: foreign, expectedHlc: foreign.sync.hlc),
      throwsA(KnowledgeEditFailure.missing),
    );
    expect(
      (await repository.findNote(
        ownerUserId: 'another-owner',
        id: foreign.id,
      ))!.sync.hlc,
      foreign.sync.hlc,
    );
  });

  test(
    'Decision editing retains canonical review fields and creation identity',
    () async {
      final current = _decision(
        1,
        actual: 'Existing outcome',
        status: DecisionStatus.verified,
      );
      await repository.upsertDecision(current);
      final saved = await editor.saveDecision(
        draft: _decision(9, question: 'Edited question'),
        expectedHlc: current.sync.hlc,
      );
      expect(saved.question, 'Edited question');
      expect(saved.actualOutcomeMd, 'Existing outcome');
      expect(saved.status, DecisionStatus.verified);
      expect(saved.decidedAt.toUtc(), current.decidedAt.toUtc());
    },
  );

  test('review preserves concurrent text edits but rejects concurrent review changes', () async {
    final baseline = _decision(1);
    await repository.upsertDecision(_decision(2, question: 'Newer question'));
    const draft = KnowledgeDecisionReviewDraft(
      reviewDate: null,
      revisitConditions: [],
      actualOutcomeMd: 'Verified outcome',
      status: DecisionStatus.verified,
    );
    await reviewer.review(baseline: baseline, draft: draft);
    final saved = (await repository.findDecision(
      ownerUserId: _owner,
      id: baseline.id,
    ))!;
    expect(saved.question, 'Newer question');
    expect(saved.actualOutcomeMd, 'Verified outcome');
    final depth = await outbox.depth();
    await expectLater(
      reviewer.review(baseline: baseline, draft: draft),
      throwsA(KnowledgeEditFailure.changed),
    );
    await reviewer.review(
      baseline: saved,
      draft: KnowledgeDecisionReviewDraft.fromDecision(saved),
    );
    expect(await outbox.depth(), depth);
  });

  test(
    'relation add validates both live owner-scoped endpoints atomically',
    () async {
      await repository.upsertNote(_note('source', 1));
      final depth = await outbox.depth();
      await expectLater(
        relations.add(
          fromKind: 'note',
          fromId: 'source',
          toKind: 'note',
          toId: 'missing',
        ),
        throwsA(KnowledgeEditFailure.missing),
      );
      expect(
        await repository.listRelationsForObject(
          ownerUserId: _owner,
          kind: 'note',
          id: 'source',
        ),
        isEmpty,
      );
      expect(await outbox.depth(), depth);
    },
  );

  test('relation removal can be undone until its source is deleted', () async {
    await repository.upsertNote(_note('source', 1));
    await repository.upsertNote(_note('target', 2));
    await relations.add(
      fromKind: 'note',
      fromId: 'source',
      toKind: 'note',
      toId: 'target',
    );
    final original = (await repository.listRelationsForObject(
      ownerUserId: _owner,
      kind: 'note',
      id: 'source',
    )).single;
    final receipt = await relations.remove(original);
    expect(
      await repository.listRelationsForObject(
        ownerUserId: _owner,
        kind: 'note',
        id: 'source',
      ),
      isEmpty,
    );
    await relations.restore(receipt);
    final restored = (await repository.listRelationsForObject(
      ownerUserId: _owner,
      kind: 'note',
      id: 'source',
    )).single;
    expect(restored.id, original.id);
    expect(restored.createdAt, original.createdAt);
    final secondReceipt = await relations.remove(restored);
    await repository.deleteEntry(
      kind: KnowledgeEntryKind.note,
      id: 'target',
      sync: _sync(3),
    );
    await expectLater(
      relations.restore(secondReceipt),
      throwsA(KnowledgeEditFailure.missing),
    );
    expect(
      await repository.listRelationsForObject(
        ownerUserId: _owner,
        kind: 'note',
        id: 'source',
      ),
      isEmpty,
    );
  });
}

SyncMeta _sync(int tick, {String owner = _owner}) {
  final now = DateTime.utc(2026, 8, 30, 10, 0, tick);
  return SyncMeta(
    ownerUserId: owner,
    updatedAt: now,
    updatedByDevice: 'mutation-device',
    hlc: Hlc(
      wallMillis: now.millisecondsSinceEpoch,
      counter: 0,
      nodeId: 'mutation-device',
    ),
  );
}

KnowledgeNote _note(
  String id,
  int tick, {
  String title = 'Note',
  String owner = _owner,
}) => KnowledgeNote(
  id: id,
  title: title,
  bodyMd: 'Body',
  createdAt: _sync(tick).updatedAt,
  sync: _sync(tick, owner: owner),
);

KnowledgeDecision _decision(
  int tick, {
  String question = 'Question',
  String? actual,
  DecisionStatus status = DecisionStatus.active,
}) => KnowledgeDecision(
  id: 'decision',
  question: question,
  options: [DecisionOption(label: 'Proceed')],
  selectedLabel: 'Proceed',
  rationaleMd: 'Rationale',
  actualOutcomeMd: actual,
  status: status,
  decidedAt: _sync(tick).updatedAt,
  sync: _sync(tick),
);
