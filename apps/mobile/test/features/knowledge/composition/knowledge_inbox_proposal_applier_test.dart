import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/knowledge/composition/knowledge_inbox_proposal_applier.dart';
import 'package:naviwealth/features/knowledge/data/inbox_triage_repository.dart';
import 'package:naviwealth/features/knowledge/data/knowledge_repository.dart';
import 'package:naviwealth/features/knowledge/domain/knowledge_models.dart';

import '../../../core/persistence/test_database.dart';

const _owner = 'u-test';

void main() {
  late AppDatabase db;
  late KnowledgeRepository repo;
  late KnowledgeInboxProposalApplier applier;
  final created = DateTime.utc(2026, 1, 1);

  setUp(() {
    db = makeTestDatabase();
    repo = KnowledgeRepository(db: db, outbox: InMemoryOutboxStore());
    applier = KnowledgeInboxProposalApplier(
      repo: repo,
      ownerUserId: _owner,
      stamp: () async => SyncMeta(
        ownerUserId: _owner,
        updatedAt: created.add(const Duration(minutes: 1)),
        updatedByDevice: 'dev',
        hlc: Hlc.zero('dev'),
      ),
    );
  });

  tearDown(() async => db.close());

  KnowledgeNote note() => KnowledgeNote(
    id: 'n1',
    title: 'Choose a database',
    bodyMd: 'Compare the options.',
    tags: const ['architecture'],
    createdAt: created,
    sync: SyncMeta(
      ownerUserId: _owner,
      updatedAt: created,
      updatedByDevice: 'dev',
      hlc: Hlc.zero('dev'),
    ),
  );

  KnowledgeDecision decision(String id) => KnowledgeDecision(
    id: id,
    question: 'Existing decision',
    options: <DecisionOption>[
      DecisionOption(label: 'A'),
      DecisionOption(label: 'B'),
    ],
    selectedLabel: 'A',
    rationaleMd: '',
    principleIds: const <String>[],
    assumptionIds: const <String>[],
    status: DecisionStatus.active,
    decidedAt: created,
    sync: note().sync,
  );

  test('classification promotes Note to a first-class Decision', () async {
    await repo.upsertNote(note());
    final proposal = InboxProposal(
      kind: InboxProposalKind.classification,
      summaryZh: 'classification',
      payload: const {'kind': 'decision'},
      status: InboxProposalStatus.pending,
    );

    final first = await applier.accept(note: note(), proposal: proposal);
    final second = await applier.accept(note: note(), proposal: proposal);

    expect(first!.kind, KnowledgeEntryKind.decision);
    expect(second!.id, first.id);
    final decision = await repo.findDecision(ownerUserId: _owner, id: first.id);
    expect(decision, isNotNull);
    expect(decision!.question, 'Choose a database');
    expect(decision.status, DecisionStatus.draft);
    expect(decision.rationaleMd, 'Compare the options.');
    final source = await repo.findNote(ownerUserId: _owner, id: 'n1');
    expect(source!.promotedToKind, KnowledgeEntryKind.decision.name);
    expect(source.promotedToId, first.id);
    expect(await repo.listNotes(ownerUserId: _owner), isEmpty);
  });

  test('classification promotes Note to a first-class Concept', () async {
    await repo.upsertNote(note());

    final result = await applier.accept(
      note: note(),
      proposal: InboxProposal(
        kind: InboxProposalKind.classification,
        summaryZh: 'classification',
        payload: const {'kind': 'concept'},
        status: InboxProposalStatus.pending,
      ),
    );

    final concept = await repo.findConcept(ownerUserId: _owner, id: result!.id);
    expect(concept!.name, 'Choose a database');
    expect(concept.summaryMd, 'Compare the options.');
  });

  test(
    'accept applies tags and decision links without changing kind',
    () async {
      await repo.upsertNote(note());
      await repo.upsertDecision(decision('d1'));

      for (final proposal in <InboxProposal>[
        InboxProposal(
          kind: InboxProposalKind.tags,
          summaryZh: 'tags',
          payload: const {
            'tags': ['Flutter', 'architecture'],
            'project_tag': 'mobile',
          },
          status: InboxProposalStatus.pending,
        ),
        InboxProposal(
          kind: InboxProposalKind.linkToDecision,
          summaryZh: 'link',
          payload: const {
            'related_decision_ids': ['d1'],
          },
          status: InboxProposalStatus.pending,
        ),
      ]) {
        await applier.accept(note: note(), proposal: proposal);
      }

      final updated = await repo.findNote(ownerUserId: _owner, id: 'n1');
      expect(updated!.tags, containsAll(<String>['architecture', 'flutter']));
      expect(updated.tags, isNot(contains('decision:d1')));
      expect(updated.projectTag, 'mobile');
      expect(updated.isPromoted, isFalse);
      final relations = await repo.listRelationsFrom(
        ownerUserId: _owner,
        fromKind: KnowledgeEntryKind.note.name,
        fromId: 'n1',
      );
      expect(relations, hasLength(1));
      expect(relations.single.toKind, KnowledgeEntryKind.decision.name);
      expect(relations.single.toId, 'd1');
    },
  );

  test('classification supersedes stale tag suggestions atomically', () async {
    await repo.upsertNote(note());
    final triage = InboxTriageRepository(db: db);
    final classification = InboxProposal(
      kind: InboxProposalKind.classification,
      summaryZh: 'classification',
      payload: const <String, Object?>{'kind': 'decision'},
      status: InboxProposalStatus.pending,
    );
    await triage.upsert(
      InboxTriageRecord(
        noteId: 'n1',
        ownerUserId: _owner,
        sourceFingerprint: knowledgeNoteTriageFingerprint(note()),
        lastTriagedAt: created,
        proposals: <InboxProposal>[
          classification,
          InboxProposal(
            kind: InboxProposalKind.tags,
            summaryZh: 'tags',
            payload: const <String, Object?>{
              'tags': <String>['stale'],
            },
            status: InboxProposalStatus.pending,
          ),
        ],
      ),
    );

    await applier.acceptAndResolve(
      note: note(),
      proposal: classification,
      triage: triage,
    );

    final resolved = await triage.findForNote('n1');
    expect(resolved!.proposals[0].status, InboxProposalStatus.accepted);
    expect(resolved.proposals[1].status, InboxProposalStatus.superseded);
  });

  test('invalid payload fails instead of pretending it was applied', () async {
    await repo.upsertNote(note());

    expect(
      () => applier.accept(
        note: note(),
        proposal: InboxProposal(
          kind: InboxProposalKind.tags,
          summaryZh: 'empty tags',
          payload: const {'tags': <String>[]},
          status: InboxProposalStatus.pending,
        ),
      ),
      throwsStateError,
    );

    final unchanged = await repo.findNote(ownerUserId: _owner, id: 'n1');
    expect(unchanged!.tags, const ['architecture']);
  });
}
