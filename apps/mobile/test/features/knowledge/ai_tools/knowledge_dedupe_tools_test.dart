import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/app/production_ai_catalog.dart';
import 'package:naviwealth/core/ai/contracts/memory_record.dart';
import 'package:naviwealth/core/ai/contracts/tool_descriptor.dart';
import 'package:naviwealth/core/ai/local/embedding/embedder.dart';
import 'package:naviwealth/core/ai/local/memory/event_store.dart';
import 'package:naviwealth/core/ai/local/memory/memory_runtime.dart';
import 'package:naviwealth/core/ai/local/memory/memory_store.dart';
import 'package:naviwealth/core/ai/local/memory/providers.dart';
import 'package:naviwealth/core/ai/runtime/device/anthropic/anthropic_wire.dart';
import 'package:naviwealth/core/ai/runtime/device/device_session.dart';
import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';
import 'package:naviwealth/core/auth/current_user.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/knowledge/ai_tools/find_similar_knowledge_tool.dart';
import 'package:naviwealth/features/knowledge/ai_tools/propose_merge_tool.dart';
import 'package:naviwealth/features/knowledge/data/knowledge_repository.dart';
import 'package:naviwealth/features/knowledge/data/providers.dart';
import 'package:naviwealth/features/knowledge/domain/knowledge_models.dart';

import '../../../core/persistence/test_database.dart';

const _kOwner = 'u1';

MemoryRecord _noteMem({
  required String sourceId,
  required String title,
  String summary = '',
}) => MemoryRecord(
  id: 'know:notes:semantic:$sourceId',
  kind: MemoryKind.episodic,
  ownerUserId: _kOwner,
  scope: '*',
  source: 'know:notes',
  sourceId: sourceId,
  title: title,
  summary: summary.isEmpty ? title : summary,
  payload: const {},
  entities: const {},
  importance: 0.6,
  confidence: 0.85,
  createdAt: DateTime.utc(2026, 5, 24),
  updatedAt: DateTime.utc(2026, 5, 24),
);

Future<MemoryRuntime> _seededRuntime(List<MemoryRecord> seed) async {
  final db = makeTestDatabase();
  final rt = MemoryRuntime(
    embedder: StubEmbedder(),
    memoryStore: SqliteMemoryStore(db: db),
    eventStore: SqliteEventStore(db: db),
  );
  for (final m in seed) {
    await rt.remember(m);
  }
  return rt;
}

Future<ProviderContainer> _seededSearchContainer(
  List<MemoryRecord> seed,
) async {
  final db = makeTestDatabase();
  final repo = KnowledgeRepository(db: db, outbox: InMemoryOutboxStore());
  final rt = MemoryRuntime(
    embedder: StubEmbedder(),
    memoryStore: SqliteMemoryStore(db: db),
    eventStore: SqliteEventStore(db: db),
  );
  final sync = SyncMeta(
    ownerUserId: _kOwner,
    updatedAt: DateTime.utc(2026, 5, 24),
    updatedByDevice: 'dev',
    hlc: Hlc.zero('dev'),
  );
  for (final memory in seed) {
    await rt.remember(memory);
    if (memory.source == 'know:notes' && memory.sourceId != null) {
      await repo.upsertNote(
        KnowledgeNote(
          id: memory.sourceId!,
          title: memory.title,
          bodyMd: memory.summary,
          tags: const [],
          createdAt: sync.updatedAt,
          sync: sync,
        ),
      );
    }
  }
  final c = ProviderContainer(
    overrides: [
      memoryRuntimeProvider.overrideWith((ref) async => rt),
      knowledgeRepositoryProvider.overrideWith((ref) async => repo),
      currentUserIdProvider.overrideWithValue(() async => _kOwner),
    ],
  );
  addTearDown(c.dispose);
  addTearDown(db.close);
  return c;
}

Future<T> _withRef<T>(ProviderContainer c, Future<T> Function(Ref ref) body) {
  final probe = FutureProvider<T>((ref) => body(ref));
  c.listen(probe, (_, _) {});
  return c.read(probe.future);
}

Future<Map<String, Object?>> _invoke(
  ProviderContainer container,
  DeviceTool tool,
  Map<String, Object?> input,
) {
  return _withRef(container, (ref) async {
    final out = await tool.invoke(
      DeviceToolContext(
        ref: ref,
        session: DeviceSession(messages: const <AnthropicChatMessage>[]),
      ),
      input,
    );
    return (out! as Map).cast<String, Object?>();
  });
}

void main() {
  group('FindSimilarKnowledgeTool', () {
    const tool = FindSimilarKnowledgeTool();

    test('descriptor mirror match', () {
      expect(tool.name, 'find_similar_knowledge');
      expect(tool.inputSchema['required'], <String>['text']);
      final d = productionToolDescriptors['find_similar_knowledge'];
      expect(d, isNotNull);
      expect(d!.access, Access.read);
      expect(d.sideEffect, SideEffect.none);
    });

    test('rejects empty text', () async {
      final rt = await _seededRuntime(const []);
      final c = ProviderContainer(
        overrides: [
          memoryRuntimeProvider.overrideWith((ref) async => rt),
          currentUserIdProvider.overrideWithValue(() async => _kOwner),
        ],
      );
      addTearDown(c.dispose);
      final out = await _invoke(c, tool, const {'text': '   '});
      expect(out['code'], 'bad_request');
    });

    test('returns note candidates and honours exclude_id', () async {
      // StubEmbedder tokenises on whitespace, so use shared-token ASCII
      // text to get a deterministic positive cosine for both notes (CJK
      // strings collapse to one opaque token → random sign). We're
      // exercising the tool mechanics, not embedder quality.
      final c = await _seededSearchContainer([
        _noteMem(sourceId: 'n1', title: 'hong kong card renewal reminder'),
        _noteMem(sourceId: 'n2', title: 'hong kong card renewal note'),
      ]);

      final out = await _invoke(c, tool, const {
        'text': 'hong kong card renewal',
        'types': ['note'],
        'threshold': 0.0,
      });
      final cands = (out['candidates'] as List).cast<Object?>();
      final ids = cands.map((e) => (e as Map)['id']).toSet();
      expect(ids, containsAll(<String>['n1', 'n2']));
      expect((cands.first as Map)['kind'], 'note');

      final excluded = await _invoke(c, tool, const {
        'text': 'hong kong card renewal',
        'types': ['note'],
        'threshold': 0.0,
        'exclude_id': 'n1',
      });
      final exIds = (excluded['candidates'] as List)
          .map((e) => (e as Map)['id'])
          .toSet();
      expect(exIds, isNot(contains('n1')));
    });

    test('types filter with no matching source returns empty', () async {
      final c = await _seededSearchContainer([
        _noteMem(sourceId: 'n1', title: '只索引了 note'),
      ]);

      final out = await _invoke(c, tool, const {
        'text': 'whatever',
        'types': ['concept'],
        'threshold': 0.0,
      });
      expect(out['candidates'], isEmpty);
    });
  });

  group('ProposeMergeTool', () {
    const tool = ProposeMergeTool();
    final created = DateTime.utc(2026, 1, 1);

    SyncMeta meta() => SyncMeta(
      ownerUserId: _kOwner,
      updatedAt: created,
      updatedByDevice: 'dev',
      hlc: Hlc.zero('dev'),
    );

    Future<ProviderContainer> repoContainer(
      Future<void> Function(KnowledgeRepository repo) seed,
    ) async {
      final db = makeTestDatabase();
      final repo = KnowledgeRepository(db: db, outbox: InMemoryOutboxStore());
      await seed(repo);
      final c = ProviderContainer(
        overrides: [
          knowledgeRepositoryProvider.overrideWith((ref) async => repo),
          currentUserIdProvider.overrideWithValue(() async => _kOwner),
        ],
      );
      addTearDown(c.dispose);
      addTearDown(db.close);
      return c;
    }

    test('descriptor mirror match', () {
      expect(tool.name, 'propose_merge');
      expect(tool.inputSchema['required'], <String>[
        'entity_type',
        'primary_id',
        'duplicate_ids',
        'reason',
      ]);
      final d = productionToolDescriptors['propose_merge'];
      expect(d, isNotNull);
      expect(d!.access, Access.propose);
      expect(d.requiresConfirmation, Confirmation.oneTap);
      expect(d.sideEffect, SideEffect.deviceLocalWrite);
    });

    test('builds a knowledge_merge envelope with diff', () async {
      final c = await repoContainer((repo) async {
        await repo.upsertNote(
          KnowledgeNote(
            id: 'keep',
            title: '港卡续期',
            bodyMd: '',
            tags: const ['hk'],
            createdAt: created,
            sync: meta(),
          ),
        );
        await repo.upsertNote(
          KnowledgeNote(
            id: 'dup',
            title: '香港卡续',
            bodyMd: '',
            tags: const ['reminder'],
            createdAt: created,
            sync: meta(),
          ),
        );
      });

      final out = await _invoke(c, tool, const {
        'entity_type': 'note',
        'primary_id': 'keep',
        'duplicate_ids': ['dup'],
        'reason': '同一张港卡的续期提醒',
      });

      expect(out['kind'], 'knowledge_merge');
      expect(out['status'], 'ready');
      expect(out['summary_zh'], contains('港卡续期'));
      final payload = (out['payload'] as Map).cast<String, Object?>();
      expect(payload['entity_type'], 'note');
      expect(payload['primary_id'], 'keep');
      expect(payload['duplicate_ids'], <String>['dup']);
      final diff = (payload['diff'] as Map).cast<String, Object?>();
      expect(diff['kept'], '港卡续期');
      expect(diff['removed'], <String>['香港卡续']);
      expect((diff['merged_tags'] as List).toSet(), {'hk', 'reminder'});
    });

    test('rejects unsupported entity_type', () async {
      final c = await repoContainer((_) async {});
      // `routine` is a first-class type but not merge-able; note/concept/
      // principle/assumption/decision/experiment are the supported set.
      final out = await _invoke(c, tool, const {
        'entity_type': 'routine',
        'primary_id': 'a',
        'duplicate_ids': ['b'],
        'reason': 'x',
      });
      expect(out['code'], 'bad_request');
    });

    test('reports missing ids as not_found', () async {
      final c = await repoContainer((repo) async {
        await repo.upsertNote(
          KnowledgeNote(
            id: 'keep',
            title: 't',
            bodyMd: '',
            tags: const [],
            createdAt: created,
            sync: meta(),
          ),
        );
      });
      final out = await _invoke(c, tool, const {
        'entity_type': 'note',
        'primary_id': 'keep',
        'duplicate_ids': ['ghost'],
        'reason': 'x',
      });
      expect(out['code'], 'not_found');
      expect((out['missing'] as List), contains('ghost'));
    });
  });
}
