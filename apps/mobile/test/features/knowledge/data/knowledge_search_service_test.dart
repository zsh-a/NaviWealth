import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/contracts/memory_record.dart';
import 'package:naviwealth/core/ai/local/embedding/embedder.dart';
import 'package:naviwealth/core/ai/local/memory/event_store.dart';
import 'package:naviwealth/core/ai/local/memory/memory_runtime.dart';
import 'package:naviwealth/core/ai/local/memory/memory_store.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/knowledge/data/knowledge_memory_indexer_support.dart';
import 'package:naviwealth/features/knowledge/data/knowledge_repository.dart';
import 'package:naviwealth/features/knowledge/data/knowledge_search_service.dart';
import 'package:naviwealth/features/knowledge/domain/knowledge_models.dart';

import '../../../core/persistence/test_database.dart';

const String _owner = 'knowledge-search-user';
const String _device = 'knowledge-search-device';

SyncMeta _sync(int tick) {
  final now = DateTime.utc(2026, 8, 30, 10, 0, tick);
  return SyncMeta(
    ownerUserId: _owner,
    updatedAt: now,
    updatedByDevice: _device,
    hlc: Hlc(
      wallMillis: now.millisecondsSinceEpoch,
      counter: 0,
      nodeId: _device,
    ),
  );
}

KnowledgeNote _note({
  required String id,
  required String title,
  required String body,
  required int tick,
}) => KnowledgeNote(
  id: id,
  title: title,
  bodyMd: body,
  tags: const <String>[],
  createdAt: _sync(tick).updatedAt,
  sync: _sync(tick),
);

MemoryRuntime _runtime(AppDatabase database, Embedder embedder) =>
    MemoryRuntime(
      embedder: embedder,
      memoryStore: SqliteMemoryStore(db: database),
      eventStore: SqliteEventStore(db: database),
    );

final class _UnavailableEmbedder implements Embedder {
  @override
  int get dimension => 32;

  @override
  String get fingerprint => 'unavailable-test-embedder';

  @override
  Future<List<double>> embed(String text) async {
    throw StateError('Embedding runtime unavailable.');
  }
}

void main() {
  late AppDatabase database;
  late KnowledgeRepository repository;

  setUp(() {
    database = makeTestDatabase();
    repository = KnowledgeRepository(
      db: database,
      outbox: InMemoryOutboxStore(),
    );
  });

  tearDown(() => database.close());

  test(
    'uses canonical lexical search when the embedder is unavailable',
    () async {
      await repository.upsertNote(
        _note(
          id: 'offline-match',
          title: 'Renovation budget',
          body: 'Keep the contingency above ten percent.',
          tick: 1,
        ),
      );
      final service = KnowledgeSearchService(
        repository: repository,
        memoryRuntime: _runtime(database, _UnavailableEmbedder()),
      );

      final hits = await service.searchKnowledge(
        ownerUserId: _owner,
        query: 'Renovation budget',
      );

      expect(hits.map((hit) => hit.id), contains('offline-match'));
      expect(hits.first.semanticScore, isNull);
      expect(hits.first.lexicalScore, 1);
    },
  );

  test('partial semantic index cannot hide an unindexed exact match', () async {
    final indexed = _note(
      id: 'indexed-unrelated',
      title: 'Project archive',
      body: 'Old project material.',
      tick: 1,
    );
    final exact = _note(
      id: 'unindexed-exact',
      title: 'Renovation budget',
      body: 'The current working budget.',
      tick: 2,
    );
    await repository.upsertNote(indexed);
    await repository.upsertNote(exact);
    final runtime = _runtime(database, StubEmbedder());
    await runtime.remember(
      MemoryRecord(
        id: '$kKnowledgeNoteMemorySource:episodic:${indexed.id}',
        kind: MemoryKind.episodic,
        ownerUserId: _owner,
        scope: '*',
        source: kKnowledgeNoteMemorySource,
        sourceId: indexed.id,
        title: indexed.title,
        summary: indexed.bodyMd,
        payload: const <String, Object?>{},
        entities: const <String>{},
        importance: 0.5,
        confidence: 0.85,
        createdAt: indexed.createdAt,
        updatedAt: indexed.sync.updatedAt,
      ),
    );
    final service = KnowledgeSearchService(
      repository: repository,
      memoryRuntime: runtime,
    );

    final hits = await service.searchKnowledge(
      ownerUserId: _owner,
      query: 'Renovation budget',
    );

    expect(hits.first.id, 'unindexed-exact');
    expect(hits.first.semanticScore, isNull);
    expect(hits.first.lexicalScore, 1);
  });
}
