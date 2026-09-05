import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/core/time/current_time_provider.dart';
import 'package:naviwealth/features/knowledge/application/knowledge_decision_from_note_service.dart';
import 'package:naviwealth/features/knowledge/data/knowledge_repository.dart';
import 'package:naviwealth/features/knowledge/data/providers.dart';
import 'package:naviwealth/features/knowledge/domain/knowledge_models.dart';

import '../../../core/persistence/test_database.dart';
import '../../../core/sync/_outbox_test_ext.dart';
import '../../finance/data/repositories/_stub_stamper.dart';

const _owner = 'knowledge-user';
const _device = 'knowledge-device';

SyncMeta _sync(int tick, {DateTime? deletedAt}) {
  final now = DateTime.utc(2026, 8, 29, 10, 0, tick);
  return SyncMeta(
    ownerUserId: _owner,
    updatedAt: now,
    updatedByDevice: _device,
    hlc: Hlc(
      wallMillis: now.millisecondsSinceEpoch,
      counter: 0,
      nodeId: _device,
    ),
    deletedAt: deletedAt,
  );
}

KnowledgeNote _note(
  String id,
  int tick, {
  String? title,
  String? sourceUrl,
  List<String>? tags,
}) => KnowledgeNote(
  id: id,
  title: title ?? id,
  bodyMd: 'body $id',
  sourceUrl: sourceUrl,
  tags: tags ?? <String>['tag-$id'],
  createdAt: _sync(tick).updatedAt,
  sync: _sync(tick),
);

KnowledgeDecision _decision(
  String id,
  int tick, {
  DateTime? reviewDate,
  DecisionStatus status = DecisionStatus.active,
  SyncMeta? sync,
}) => KnowledgeDecision(
  id: id,
  question: 'question $id',
  options: <DecisionOption>[DecisionOption(label: 'yes')],
  selectedLabel: 'yes',
  rationaleMd: 'because',
  status: status,
  reviewDate: reviewDate,
  decidedAt: _sync(tick).updatedAt,
  sync: sync ?? _sync(tick),
);

void main() {
  late AppDatabase database;
  late InMemoryOutboxStore outbox;
  late KnowledgeRepository repository;

  setUp(() {
    database = makeTestDatabase();
    outbox = InMemoryOutboxStore();
    repository = KnowledgeRepository(db: database, outbox: outbox);
  });

  tearDown(() => database.close());

  test(
    'due reviews refresh when time advances without a database write',
    () async {
      final due = DateTime.utc(2026, 9, 6);
      await repository.upsertDecision(_decision('timed', 0, reviewDate: due));
      final container = ProviderContainer(
        overrides: [
          knowledgeRepositoryProvider.overrideWith((_) async => repository),
          knowledgeOwnerUserIdProvider.overrideWith((_) async => _owner),
          currentTimeProvider.overrideWith(_ReviewClock.new),
        ],
      );
      final subscription = container.listen(
        knowledgeDueReviewsProvider,
        (_, _) {},
      );
      expect(await container.read(knowledgeDueReviewsProvider.future), isEmpty);
      (container.read(currentTimeProvider.notifier) as _ReviewClock).advance(
        due,
      );
      await container.pump();
      expect(
        (await container.read(knowledgeDueReviewsProvider.future)).single.id,
        'timed',
      );
      subscription.close();
      container.dispose();
    },
  );

  test('library windows grow past 200 with stable updated ordering', () async {
    for (var i = 0; i < 205; i++) {
      await repository.upsertNote(_note('note-$i', i));
      await repository.upsertDecision(_decision('decision-$i', i));
    }
    final first = await repository
        .watchNotes(ownerUserId: _owner, limit: 51, orderByUpdated: true)
        .first;
    final all = await repository
        .watchNotes(ownerUserId: _owner, limit: 251, orderByUpdated: true)
        .first;
    expect(first.length, 51);
    expect(first.first.id, 'note-204');
    expect(all.length, 205);
    expect(all.last.id, 'note-0');
    final decisions = await repository
        .watchDecisions(ownerUserId: _owner, limit: 251, orderByUpdated: true)
        .first;
    expect(decisions.length, 205);
    expect(decisions.last.id, 'decision-0');
    final tags = await repository.watchNoteTags(ownerUserId: _owner).first;
    expect(tags, contains('tag-note-0'));
    expect(tags.length, 205);
  });

  test(
    'tag filtering precedes limit and treats SQL wildcards literally',
    () async {
      await repository.upsertNote(_note('old', 0, tags: ['100%', 'a_b']));
      await repository.upsertNote(_note('new', 1, tags: ['1000', 'axb']));
      for (final tag in ['100%', 'a_b']) {
        final hits = await repository
            .watchNotes(
              ownerUserId: _owner,
              tag: tag,
              limit: 1,
              orderByUpdated: true,
            )
            .first;
        expect(hits.single.id, 'old');
      }
    },
  );

  test(
    'schema contains no legacy KnowledgeOS objects or side tables',
    () async {
      final rows = await database
          .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
          .get();
      final tables = rows.map((row) => row.read<String>('name')).toSet();
      expect(
        tables,
        containsAll(<String>{
          'knowledge_notes',
          'knowledge_decisions',
          'knowledge_relations',
        }),
      );
      for (final legacy in <String>[
        'knowledge_principles',
        'knowledge_assumptions',
        'knowledge_concepts',
        'knowledge_experiments',
        'knowledge_routines',
        'knowledge_inbox_triage',
        'knowledge_attachments',
      ]) {
        expect(tables, isNot(contains(legacy)));
      }

      final decisionColumns = await database
          .customSelect('PRAGMA table_info(knowledge_decisions)')
          .get();
      expect(
        decisionColumns.map((row) => row.read<String>('name')),
        isNot(contains('context_snapshot_json')),
      );
    },
  );

  test(
    'due review stream includes old decisions beyond the browse limit',
    () async {
      final asOf = DateTime.utc(2026, 9, 1);
      final dueDate = DateTime.utc(2026, 8, 1);
      await repository.transaction(() async {
        await repository.upsertDecision(
          _decision('old-due', 0, reviewDate: dueDate),
        );
        for (var i = 1; i <= 205; i++) {
          await repository.upsertDecision(_decision('new-$i', i));
        }
        await repository.upsertDecision(
          _decision('future', 210, reviewDate: DateTime.utc(2099)),
        );
        await repository.upsertDecision(
          _decision(
            'verified',
            211,
            reviewDate: dueDate,
            status: DecisionStatus.verified,
          ),
        );
        await repository.upsertDecision(
          _decision(
            'deleted',
            212,
            reviewDate: dueDate,
            sync: _sync(212, deletedAt: asOf),
          ),
        );
        await repository.upsertDecision(
          _decision(
            'other-owner',
            213,
            reviewDate: dueDate,
            sync: _sync(213).copyWith(ownerUserId: 'other'),
          ),
        );
      });
      expect(
        (await repository.watchDecisions(ownerUserId: _owner, limit: 200).first)
            .any((d) => d.id == 'old-due'),
        isFalse,
      );
      final stream = StreamIterator(
        repository.watchDueReviews(ownerUserId: _owner, asOf: asOf),
      );
      addTearDown(stream.cancel);
      expect(await stream.moveNext(), isTrue);
      expect(stream.current.map((d) => d.id), ['old-due']);
      expect(
        (await repository.listDueReviews(
          ownerUserId: _owner,
          asOf: asOf,
        )).map((d) => d.id),
        ['old-due'],
      );
      await repository.upsertDecision(
        _decision(
          'old-due',
          0,
          reviewDate: dueDate,
          status: DecisionStatus.verified,
        ),
      );
      expect(await stream.moveNext(), isTrue);
      expect(stream.current, isEmpty);
    },
  );

  test('stores only canonical notes and decisions', () async {
    await repository.upsertNote(_note('n1', 1));
    await repository.upsertDecision(_decision('d1', 2));

    expect(await repository.listNotes(ownerUserId: _owner), hasLength(1));
    expect(await repository.listDecisions(ownerUserId: _owner), hasLength(1));
    expect(
      outbox.queued,
      containsAll(<({String table, String rowId})>[
        (table: 'knowledge_notes', rowId: 'n1'),
        (table: 'knowledge_decisions', rowId: 'd1'),
      ]),
    );
  });

  test('normalizes and finds a live Note by exact source URL', () async {
    await repository.upsertNote(
      _note(
        'source-note',
        1,
        sourceUrl: 'HTTPS://WWW.Example.COM:443/article#section',
      ),
    );

    final found = await repository.findNoteBySourceUrl(
      ownerUserId: _owner,
      sourceUrl: 'https://www.example.com/article#other',
    );

    expect(found?.id, 'source-note');
    expect(found?.sourceUrl, 'https://www.example.com/article');
    expect(
      await repository.findNoteBySourceUrl(
        ownerUserId: _owner,
        sourceUrl: 'https://www.example.com/article',
        excludeId: 'source-note',
      ),
      isNull,
    );
  });

  test('deleting an entry also tombstones its relations', () async {
    await repository.upsertNote(_note('n1', 1));
    await repository.upsertDecision(_decision('d1', 2));
    await repository.upsertRelation(
      KnowledgeRelation(
        id: 'r1',
        fromKind: 'note',
        fromId: 'n1',
        relation: KnowledgeRelationType.relatedTo,
        toKind: 'decision',
        toId: 'd1',
        createdAt: _sync(3).updatedAt,
        sync: _sync(3),
      ),
    );

    await repository.deleteEntry(
      kind: KnowledgeEntryKind.note,
      id: 'n1',
      sync: _sync(4, deletedAt: _sync(4).updatedAt),
    );

    expect(await repository.listNotes(ownerUserId: _owner), isEmpty);
    expect(
      await repository.listRelationsForObject(
        ownerUserId: _owner,
        kind: 'decision',
        id: 'd1',
      ),
      isEmpty,
    );
  });

  test('creates a Decision and directed source relation atomically', () async {
    await repository.upsertNote(_note('n-source', 1));
    final service = KnowledgeDecisionFromNoteService(
      repository: repository,
      stamper: makeStubStamper(userId: _owner),
    );

    final decision = await service.create(
      noteId: 'n-source',
      question: 'Should we adopt the proposal?',
      options: <DecisionOption>[
        DecisionOption(label: 'Adopt it'),
        DecisionOption(label: 'Keep the current approach'),
      ],
      selectedLabel: 'Adopt it',
      rationaleMd: 'The source note contains the supporting evidence.',
    );

    final relations = await repository.listRelationsForObject(
      ownerUserId: _owner,
      kind: KnowledgeEntryKind.decision.name,
      id: decision.id,
    );
    expect(relations, hasLength(1));
    expect(relations.single.fromKind, KnowledgeEntryKind.note.name);
    expect(relations.single.fromId, 'n-source');
    expect(relations.single.relation, KnowledgeRelationType.informs);
    expect(relations.single.toKind, KnowledgeEntryKind.decision.name);
    expect(relations.single.toId, decision.id);
    expect(
      outbox.queued,
      containsAll(<({String table, String rowId})>[
        (table: 'knowledge_decisions', rowId: decision.id),
        (table: 'knowledge_relations', rowId: relations.single.id),
      ]),
    );
  });

  test('does not create a Decision when its source Note is missing', () async {
    final decision = _decision('d-orphan', 5);

    await expectLater(
      repository.createDecisionFromNote(
        noteId: 'missing-note',
        decision: decision,
      ),
      throwsStateError,
    );

    expect(
      await repository.findDecision(ownerUserId: _owner, id: decision.id),
      isNull,
    );
    expect(
      await repository.listRelationsForObject(
        ownerUserId: _owner,
        kind: KnowledgeEntryKind.decision.name,
        id: decision.id,
      ),
      isEmpty,
    );
  });

  test(
    'merges duplicate notes without exposing a typed-object taxonomy',
    () async {
      final primary = _note('n1', 1, title: 'Primary');
      final duplicate = _note('n2', 2, title: 'Duplicate');
      await repository.upsertNote(primary);
      await repository.upsertNote(duplicate);
      var tick = 10;

      final merged = await repository.mergeNotes(
        primary: primary,
        duplicates: <KnowledgeNote>[duplicate],
        stamp: () async => _sync(tick++),
      );

      expect(merged.id, 'n1');
      expect(merged.tags, containsAll(<String>['tag-n1', 'tag-n2']));
      expect(await repository.listNotes(ownerUserId: _owner), hasLength(1));
      final tombstone = await repository.findNote(
        ownerUserId: _owner,
        id: 'n2',
      );
      expect(tombstone?.mergedIntoId, 'n1');
      expect(tombstone?.sync.deletedAt, isNotNull);
    },
  );
}

class _ReviewClock extends CurrentTime {
  void advance(DateTime time) => state = time;
  @override
  DateTime build() => DateTime.utc(2026, 9, 5);
}
