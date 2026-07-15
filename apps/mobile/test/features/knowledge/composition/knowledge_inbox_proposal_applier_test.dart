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

  test('accept applies classification, tags, and decision links', () async {
    await repo.upsertNote(note());

    for (final proposal in <InboxProposal>[
      InboxProposal(
        kind: InboxProposalKind.classification,
        summaryZh: 'classification',
        payload: const {'kind': 'decision_candidate'},
        status: InboxProposalStatus.pending,
      ),
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
    expect(
      updated!.tags,
      containsAll(<String>[
        'architecture',
        'kind:decision_candidate',
        'flutter',
        'decision:d1',
      ]),
    );
    expect(updated.projectTag, 'mobile');
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
