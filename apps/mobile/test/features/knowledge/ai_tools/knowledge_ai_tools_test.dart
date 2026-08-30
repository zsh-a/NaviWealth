import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/composition/proposal_apply_state.dart';
import 'package:naviwealth/core/ai/composition/proposal_plan.dart';
import 'package:naviwealth/core/ai/contracts/memory_record.dart';
import 'package:naviwealth/core/ai/local/memory/providers.dart';
import 'package:naviwealth/core/ai/runtime/device/device_session.dart';
import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/persistence/providers.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/core/sync/outbox_provider.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/knowledge/composition/knowledge_proposal_applier.dart';
import 'package:naviwealth/features/knowledge/data/knowledge_memory_indexer_support.dart';
import 'package:naviwealth/features/knowledge/data/knowledge_repository.dart';
import 'package:naviwealth/features/knowledge/domain/knowledge_models.dart';
import 'package:naviwealth/features/knowledge/knowledge_ai_tools.dart';

import '../../../core/persistence/test_database.dart';
import '../../../core/sync/_outbox_test_ext.dart';

const _owner = 'knowledge-tools-user';
const _otherOwner = 'knowledge-tools-other-user';
const _device = 'knowledge-tools-device';

void main() {
  late AppDatabase database;
  late InMemoryOutboxStore outbox;
  late ProviderContainer container;
  late KnowledgeRepository repository;

  setUp(() {
    database = makeTestDatabase();
    outbox = InMemoryOutboxStore();
    repository = KnowledgeRepository(db: database, outbox: outbox);
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWith((ref) async => database),
        outboxStoreProvider.overrideWith((ref) async => outbox),
        currentUserIdProvider.overrideWithValue(() async => _owner),
        mutationStamperProvider.overrideWith((ref) async => _stamper()),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await database.close();
  });

  test('catalog remains bounded to the seven documented Knowledge tools', () {
    expect(kKnowledgeDeviceTools.map((tool) => tool.name), <String>[
      'recall_decision',
      'list_due_reviews',
      'search_notes',
      'search_knowledge',
      'find_similar_knowledge',
      'propose_capture',
      'propose_merge',
    ]);
    expect(
      kKnowledgeAssistantDeviceTools.map((tool) => tool.name),
      isNot(contains('propose_merge')),
    );
  });

  test('read tools stay owner-scoped and return verifiable evidence', () async {
    final note = _note(
      id: 'note-owner',
      owner: _owner,
      title: 'Automation roadmap',
      body: 'Automate the workflow with a reversible pilot.',
      tags: const <String>['work'],
      tick: 1,
    );
    final foreign = _note(
      id: 'note-foreign',
      owner: _otherOwner,
      title: 'Automation roadmap from another owner',
      body: 'Must remain invisible.',
      tick: 2,
    );
    final decision = _decision(
      id: 'decision-owner',
      question: 'Should we automate the workflow?',
      reviewDate: DateTime.utc(2020),
      tick: 3,
    );
    await repository.upsertNote(note);
    await repository.upsertNote(foreign);
    await repository.upsertDecision(decision);

    final searchNotes = await _invokeByName(container, 'search_notes', {
      'query': 'automation',
      'tags': <String>['work'],
    }) as Map<Object?, Object?>;
    final notes = searchNotes['notes']! as List<Object?>;
    expect(notes, hasLength(1));
    expect((notes.single! as Map<Object?, Object?>)['id'], note.id);
    expect(
      (searchNotes['evidence']! as List<Object?>).single,
      containsPair('entity_table', 'knowledge_notes'),
    );

    final searchKnowledge = await _invokeByName(
      container,
      'search_knowledge',
      const <String, Object?>{'query': 'workflow'},
    ) as Map<Object?, Object?>;
    expect(
      (searchKnowledge['results']! as List<Object?>).map(
        (raw) => (raw! as Map<Object?, Object?>)['id'],
      ),
      containsAll(<String>[note.id, decision.id]),
    );

    final recalled = await _invokeByName(
      container,
      'recall_decision',
      const <String, Object?>{'query': 'automate'},
    ) as Map<Object?, Object?>;
    expect(
      ((recalled['decisions']! as List<Object?>).single!
          as Map<Object?, Object?>)['id'],
      decision.id,
    );

    final due = await _invokeByName(
      container,
      'list_due_reviews',
      const <String, Object?>{'as_of': '2026-08-30T00:00:00Z'},
    ) as Map<Object?, Object?>;
    expect(
      ((due['decisions']! as List<Object?>).single!
          as Map<Object?, Object?>)['id'],
      decision.id,
    );

    final runtime = await container.read(memoryRuntimeProvider.future);
    await runtime.remember(
      MemoryRecord(
        id: '$kKnowledgeNoteMemorySource:episodic:${note.id}',
        kind: MemoryKind.episodic,
        ownerUserId: _owner,
        scope: '*',
        source: kKnowledgeNoteMemorySource,
        sourceId: note.id,
        title: note.title,
        summary: note.bodyMd,
        payload: const <String, Object?>{},
        entities: const <String>{},
        importance: 0.5,
        confidence: 0.9,
        createdAt: note.createdAt,
        updatedAt: note.sync.updatedAt,
      ),
    );
    final similar = await _invokeByName(
      container,
      'find_similar_knowledge',
      <String, Object?>{
        'text': '${note.title} ${note.bodyMd}',
        'types': <String>['note'],
        'threshold': 0,
      },
    ) as Map<Object?, Object?>;
    expect(
      ((similar['candidates']! as List<Object?>).single!
          as Map<Object?, Object?>)['id'],
      note.id,
    );
  });

  test(
    'capture proposal does not write before apply and undo tombstones it',
    () async {
      final invalid = await _invokeByName(
        container,
        'propose_capture',
        <String, Object?>{
          'kind': 'decision',
          'title': 'Choose an approach',
          'options': <Object?>[
            <String, Object?>{'label': 'Pilot'},
          ],
          'selected_label': 'Roll out everywhere',
        },
      ) as Map<Object?, Object?>;
      expect(invalid['code'], 'bad_request');

      final tooManyOptions = await _invokeByName(
        container,
        'propose_capture',
        <String, Object?>{
          'kind': 'decision',
          'title': 'Choose an approach',
          'options': <Object?>[
            <String, Object?>{'label': 'A'},
            <String, Object?>{'label': 'B'},
            <String, Object?>{'label': 'C'},
            <String, Object?>{'label': 'D'},
          ],
          'selected_label': 'A',
        },
      ) as Map<Object?, Object?>;
      expect(tooManyOptions['code'], 'bad_request');

      final proposal = await _invokeByName(
        container,
        'propose_capture',
        <String, Object?>{
          'kind': 'decision',
          'title': 'Choose an approach',
          'body': 'Prefer the reversible path.',
          'options': <Object?>[
            <String, Object?>{'label': 'Pilot', 'rationale': 'Limits downside'},
            <String, Object?>{'label': 'Full rollout'},
          ],
          'selected_label': 'Pilot',
        },
      );
      expect(
        await repository.listDecisions(ownerUserId: _owner),
        isEmpty,
        reason: 'a propose tool must never mutate canonical rows',
      );

      final state = await _apply(container, proposal);
      final created = await repository.findDecision(
        ownerUserId: _owner,
        id: state.appliedEntityId!,
      );
      expect(created?.selectedLabel, 'Pilot');
      expect(created?.options.map((option) => option.label), <String>[
        'Pilot',
        'Full rollout',
      ]);
      expect(created?.options.first.rationale, 'Limits downside');
      expect(
        outbox.queued,
        contains((table: 'knowledge_decisions', rowId: created!.id)),
      );

      final applier = await container.read(
        knowledgeProposalApplierProvider.future,
      );
      await applier.undo(state);
      final undone = await repository.findDecision(
        ownerUserId: _owner,
        id: created.id,
      );
      expect(undone?.sync.deletedAt, isNotNull);
    },
  );

  test(
    'merge proposal applies and restores both Note snapshots on undo',
    () async {
      final primary = _note(
        id: 'note-primary',
        owner: _owner,
        title: 'Primary note',
        body: 'Canonical body',
        tags: const <String>['primary'],
        tick: 1,
      );
      final duplicate = _note(
        id: 'note-duplicate',
        owner: _owner,
        title: 'Duplicate note',
        body: 'Additional context',
        tags: const <String>['duplicate'],
        tick: 2,
      );
      await repository.upsertNote(primary);
      await repository.upsertNote(duplicate);

      final proposal = await _invokeByName(
        container,
        'propose_merge',
        <String, Object?>{
          'entity_type': 'note',
          'primary_id': primary.id,
          'duplicate_ids': <String>[duplicate.id],
          'reason': 'Same source material',
        },
      );
      expect(
        (await repository.findNote(
          ownerUserId: _owner,
          id: duplicate.id,
        ))?.mergedIntoId,
        isNull,
      );

      final state = await _apply(container, proposal);
      final mergedPrimary = await repository.findNote(
        ownerUserId: _owner,
        id: primary.id,
      );
      final mergedDuplicate = await repository.findNote(
        ownerUserId: _owner,
        id: duplicate.id,
      );
      expect(
        mergedPrimary?.tags,
        containsAll(<String>['primary', 'duplicate']),
      );
      expect(mergedDuplicate?.mergedIntoId, primary.id);
      expect(mergedDuplicate?.sync.deletedAt, isNotNull);

      final applier = await container.read(
        knowledgeProposalApplierProvider.future,
      );
      await applier.undo(state);
      final restoredPrimary = await repository.findNote(
        ownerUserId: _owner,
        id: primary.id,
      );
      final restoredDuplicate = await repository.findNote(
        ownerUserId: _owner,
        id: duplicate.id,
      );
      expect(restoredPrimary?.tags, <String>['primary']);
      expect(restoredDuplicate?.mergedIntoId, isNull);
      expect(restoredDuplicate?.sync.deletedAt, isNull);
    },
  );
}

DeviceSession _session() => DeviceSession(messages: []);

Future<T> _withRef<T>(
  ProviderContainer container,
  Future<T> Function(Ref ref) body,
) {
  final probe = FutureProvider<T>((ref) => body(ref));
  container.listen(probe, (_, _) {});
  return container.read(probe.future);
}

Future<Object?> _invokeByName(
  ProviderContainer container,
  String name,
  Map<String, Object?> input,
) {
  final tool = kKnowledgeDeviceTools.singleWhere((tool) => tool.name == name);
  return _withRef(
    container,
    (ref) =>
        tool.invoke(DeviceToolContext(ref: ref, session: _session()), input),
  );
}

Future<ProposalApplyState> _apply(
  ProviderContainer container,
  Object? proposal,
) {
  final plan = ProposalPlan.tryParse(proposal);
  expect(plan, isA<ReadyProposalPlan>());
  return _withRef(container, (ref) async {
    final applier = await ref.read(knowledgeProposalApplierProvider.future);
    return applier.apply(plan! as ReadyProposalPlan);
  });
}

KnowledgeNote _note({
  required String id,
  required String owner,
  required String title,
  required String body,
  required int tick,
  List<String> tags = const <String>[],
}) => KnowledgeNote(
  id: id,
  title: title,
  bodyMd: body,
  tags: tags,
  createdAt: _sync(owner, tick).updatedAt,
  sync: _sync(owner, tick),
);

KnowledgeDecision _decision({
  required String id,
  required String question,
  required int tick,
  DateTime? reviewDate,
}) => KnowledgeDecision(
  id: id,
  question: question,
  options: <DecisionOption>[
    DecisionOption(label: 'Pilot'),
    DecisionOption(label: 'Keep manual'),
  ],
  selectedLabel: 'Pilot',
  rationaleMd: 'A pilot is reversible.',
  reviewDate: reviewDate,
  status: DecisionStatus.active,
  decidedAt: _sync(_owner, tick).updatedAt,
  sync: _sync(_owner, tick),
);

SyncMeta _sync(String owner, int tick) {
  final now = DateTime.utc(2026, 8, 30, 10, 0, tick);
  return SyncMeta(
    ownerUserId: owner,
    updatedAt: now,
    updatedByDevice: _device,
    hlc: Hlc(
      wallMillis: now.millisecondsSinceEpoch,
      counter: 0,
      nodeId: _device,
    ),
  );
}

MutationStamper _stamper() {
  var tick = 10;
  return MutationStamper(
    currentUserId: () async => _owner,
    deviceId: () async => _device,
    stampHlc: () async => _sync(_owner, tick++).hlc,
  );
}
