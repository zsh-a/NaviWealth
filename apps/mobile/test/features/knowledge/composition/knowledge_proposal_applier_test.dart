import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/composition/composite_proposal_applier.dart';
import 'package:naviwealth/core/ai/composition/proposal_applier.dart';
import 'package:naviwealth/core/ai/composition/proposal_apply_state.dart';
import 'package:naviwealth/core/ai/composition/proposal_plan.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/knowledge/composition/knowledge_proposal_applier.dart';
import 'package:naviwealth/features/knowledge/data/knowledge_repository.dart';
import 'package:naviwealth/features/knowledge/domain/knowledge_models.dart';

import '../../../core/persistence/test_database.dart';

const _owner = 'u-test';

void main() {
  late AppDatabase db;
  late KnowledgeRepository repo;
  late KnowledgeProposalApplier applier;
  final created = DateTime.utc(2026, 1, 1);

  var stampCounter = 0;
  Future<SyncMeta> stamp() async {
    stampCounter++;
    return SyncMeta(
      ownerUserId: _owner,
      updatedAt: created.add(Duration(seconds: stampCounter)),
      updatedByDevice: 'dev',
      hlc: Hlc.zero('dev'),
    );
  }

  setUp(() {
    stampCounter = 0;
    db = makeTestDatabase();
    repo = KnowledgeRepository(db: db, outbox: InMemoryOutboxStore());
    applier = KnowledgeProposalApplier(repo: repo, stamp: stamp);
  });

  tearDown(() async => db.close());

  KnowledgeNote note(String id, String title, List<String> tags) => KnowledgeNote(
        id: id,
        title: title,
        bodyMd: '',
        tags: tags,
        createdAt: created,
        sync: SyncMeta(
          ownerUserId: _owner,
          updatedAt: created,
          updatedByDevice: 'dev',
          hlc: Hlc.zero('dev'),
        ),
      );

  ReadyProposalPlan plan(String kind, Map<String, Object?> payload) =>
      ReadyProposalPlan(
        proposalId: 'p1',
        kind: kind,
        summaryZh: 's',
        payload: payload,
      );

  group('KnowledgeProposalApplier', () {
    test('knowledge_merge (note) merges and tombstones', () async {
      await repo.upsertNote(note('keep', '港卡续期', const ['hk']));
      await repo.upsertNote(note('dup', '香港卡续', const ['reminder']));

      final state = await applier.apply(plan('knowledge_merge', {
        'entity_type': 'note',
        'primary_id': 'keep',
        'duplicate_ids': ['dup'],
      }));

      expect(state.status, ProposalApplyStatus.applied);
      expect(state.appliedEntityId, 'keep');
      expect(state.appliedTable, 'knowledge_notes');
      // No appliedAt → no 60s undo offered.
      expect(state.appliedAt, isNull);

      final live = await repo.listNotes(ownerUserId: _owner);
      expect(live.map((n) => n.id), <String>['keep']);
      expect(live.single.tags.toSet(), {'hk', 'reminder'});
      final dup = await repo.findNote('dup');
      expect(dup!.mergedIntoId, 'keep');
    });

    test('knowledge_routine creates a routine row', () async {
      final state = await applier.apply(plan('knowledge_routine', {
        'statement': '港卡活跃',
        'interval_days': 180,
        'scope': 'finance/cards/hk',
      }));
      expect(state.status, ProposalApplyStatus.applied);
      expect(state.appliedTable, 'knowledge_routines');

      final r = await repo.findRoutine(state.appliedEntityId!);
      expect(r, isNotNull);
      expect(r!.statement, '港卡活跃');
      expect(r.intervalDays, 180);
    });

    test('knowledge_concept_link links both concepts bidirectionally', () async {
      KnowledgeConcept concept(String id, String name) => KnowledgeConcept(
            id: id,
            name: name,
            aliases: const [],
            summaryMd: '',
            relatedConceptIds: const [],
            createdAt: created,
            sync: SyncMeta(
              ownerUserId: _owner,
              updatedAt: created,
              updatedByDevice: 'dev',
              hlc: Hlc.zero('dev'),
            ),
          );
      await repo.upsertConcept(concept('c1', 'FIRE'));
      await repo.upsertConcept(concept('c2', '安全边际'));

      final state = await applier.apply(plan('knowledge_concept_link', {
        'from_concept_id': 'c1',
        'to_concept_id': 'c2',
        'relation': 'relates_to',
      }));
      expect(state.status, ProposalApplyStatus.applied);
      expect(state.appliedTable, 'knowledge_concepts');

      final c1 = await repo.findConcept('c1');
      final c2 = await repo.findConcept('c2');
      expect(c1!.relatedConceptIds, contains('c2'));
      expect(c2!.relatedConceptIds, contains('c1'));
    });

    test('merge with unsupported entity_type throws', () async {
      expect(
        () => applier.apply(plan('knowledge_merge', {
          'entity_type': 'decision',
          'primary_id': 'a',
          'duplicate_ids': ['b'],
        })),
        throwsA(isA<ProposalApplyException>()),
      );
    });

    test('unknown kind throws', () async {
      expect(
        () => applier.apply(plan('something_else', const {})),
        throwsA(isA<ProposalApplyException>()),
      );
    });
  });

  group('CompositeProposalApplier', () {
    test('routes knowledge_* to knowledge, else fallback', () async {
      final fallback = _RecordingApplier();
      final composite = CompositeProposalApplier(
        routes: [
          ProposalApplierRoute(
            applier: applier,
            kinds: kKnowledgeProposalAppliedKinds,
            tablePrefix: kKnowledgeTablePrefix,
          ),
        ],
        fallback: fallback,
      );

      await repo.upsertNote(note('keep', 'a', const []));
      await repo.upsertNote(note('dup', 'b', const []));
      final state = await composite.apply(plan('knowledge_merge', {
        'entity_type': 'note',
        'primary_id': 'keep',
        'duplicate_ids': ['dup'],
      }));
      expect(state.appliedTable, 'knowledge_notes');
      expect(fallback.applied, isEmpty, reason: 'knowledge kind never hits fallback');

      await composite.apply(plan('trade', const {}));
      expect(fallback.applied, <String>['trade']);
    });

    test('undo routes by appliedTable prefix', () async {
      final fallback = _RecordingApplier();
      final composite = CompositeProposalApplier(
        routes: [
          ProposalApplierRoute(
            applier: applier,
            kinds: kKnowledgeProposalAppliedKinds,
            tablePrefix: kKnowledgeTablePrefix,
          ),
        ],
        fallback: fallback,
      );
      // Finance table → fallback.undo.
      await composite.undo(const ProposalApplyState(
        status: ProposalApplyStatus.applied,
        appliedTable: 'journal_entries',
      ));
      expect(fallback.undone, <String>['journal_entries']);
    });
  });
}

class _RecordingApplier implements ProposalApplier {
  final List<String> applied = [];
  final List<String> undone = [];

  @override
  Future<ProposalApplyState> apply(ReadyProposalPlan plan) async {
    applied.add(plan.kind);
    return const ProposalApplyState(status: ProposalApplyStatus.applied);
  }

  @override
  Future<void> undo(ProposalApplyState state) async {
    undone.add(state.appliedTable ?? '');
  }
}
