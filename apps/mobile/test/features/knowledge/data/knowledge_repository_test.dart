import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/knowledge/data/knowledge_repository.dart';
import 'package:naviwealth/features/knowledge/domain/knowledge_models.dart';

import '../../../core/persistence/test_database.dart';
import '../../../core/sync/_outbox_test_ext.dart';

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

KnowledgeNote _note(String id, int tick, {String? title}) => KnowledgeNote(
  id: id,
  title: title ?? id,
  bodyMd: 'body $id',
  tags: <String>['tag-$id'],
  createdAt: _sync(tick).updatedAt,
  sync: _sync(tick),
);

KnowledgeDecision _decision(String id, int tick) => KnowledgeDecision(
  id: id,
  question: 'question $id',
  options: <DecisionOption>[DecisionOption(label: 'yes')],
  selectedLabel: 'yes',
  rationaleMd: 'because',
  status: DecisionStatus.active,
  decidedAt: _sync(tick).updatedAt,
  sync: _sync(tick),
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
