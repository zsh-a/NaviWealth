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
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/design_system/preferences/theme_preferences.dart';
import 'package:naviwealth/features/knowledge/ai_tools/recall_decision_tool.dart';
import 'package:naviwealth/features/knowledge/ai_tools/review_knowledge_health_tool.dart';
import 'package:naviwealth/features/knowledge/ai_tools/search_knowledge_tool.dart';
import 'package:naviwealth/features/knowledge/ai_tools/search_notes_tool.dart';
import 'package:naviwealth/features/knowledge/data/knowledge_repository.dart';
import 'package:naviwealth/features/knowledge/data/providers.dart';
import 'package:naviwealth/features/knowledge/domain/knowledge_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/persistence/test_database.dart';

const _owner = 'u1';
late SharedPreferences _prefs;

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

Future<void> _upsertMemorySource(
  KnowledgeRepository repo,
  MemoryRecord memory,
  SyncMeta sync,
) async {
  final sourceId = memory.sourceId;
  if (sourceId == null) return;
  final title = memory.title;
  final summary = memory.summary;
  switch (memory.source) {
    case 'know:notes':
      await repo.upsertNote(
        KnowledgeNote(
          id: sourceId,
          title: title,
          bodyMd: summary,
          tags: const [],
          createdAt: sync.updatedAt,
          sync: sync,
        ),
      );
      return;
    case 'know:concepts':
      await repo.upsertConcept(
        KnowledgeConcept(
          id: sourceId,
          name: title,
          aliases: const [],
          summaryMd: summary,
          relatedConceptIds: const [],
          createdAt: sync.updatedAt,
          sync: sync,
        ),
      );
      return;
    case 'know:decisions':
      await repo.upsertDecision(
        KnowledgeDecision(
          id: sourceId,
          question: title,
          options: const [],
          selectedLabel: '',
          rationaleMd: summary,
          principleIds: const [],
          assumptionIds: const [],
          status: DecisionStatus.active,
          decidedAt: sync.updatedAt,
          sync: sync,
        ),
      );
      return;
    case 'know:routines':
      await repo.upsertRoutine(
        KnowledgeRoutine(
          id: sourceId,
          statement: title,
          intervalDays: 180,
          nextDueAt: sync.updatedAt.add(const Duration(days: 180)),
          scope: '*',
          status: RoutineStatus.active,
          createdAt: sync.updatedAt,
          sync: sync,
        ),
      );
      return;
  }
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    _prefs = await SharedPreferences.getInstance();
  });

  final created = DateTime.utc(2026, 1, 1);
  SyncMeta meta() => SyncMeta(
    ownerUserId: _owner,
    updatedAt: created,
    updatedByDevice: 'dev',
    hlc: Hlc.zero('dev'),
  );

  group('SearchKnowledgeTool', () {
    const tool = SearchKnowledgeTool();

    Future<ProviderContainer> seededMemory(
      List<MemoryRecord> seed, {
      bool hydrate = true,
    }) async {
      final db = makeTestDatabase();
      final rt = MemoryRuntime(
        embedder: StubEmbedder(),
        memoryStore: SqliteMemoryStore(db: db),
        eventStore: SqliteEventStore(db: db),
      );
      final repo = KnowledgeRepository(db: db, outbox: InMemoryOutboxStore());
      for (final m in seed) {
        await rt.remember(m);
        if (hydrate) {
          await _upsertMemorySource(repo, m, meta());
        }
      }
      final c = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(_prefs),
          memoryRuntimeProvider.overrideWith((ref) async => rt),
          knowledgeRepositoryProvider.overrideWith((ref) async => repo),
          currentUserIdProvider.overrideWithValue(() async => _owner),
        ],
      );
      addTearDown(c.dispose);
      addTearDown(db.close);
      return c;
    }

    MemoryRecord mem(String source, String sourceId, String title) =>
        MemoryRecord(
          id: '$source:x:$sourceId',
          kind: MemoryKind.episodic,
          ownerUserId: _owner,
          scope: '*',
          source: source,
          sourceId: sourceId,
          title: title,
          summary: title,
          payload: const {},
          entities: const {},
          importance: 0.6,
          confidence: 0.85,
          createdAt: created,
          updatedAt: created,
        );

    test('descriptor mirror match', () {
      expect(tool.name, 'search_knowledge');
      expect(tool.inputSchema['required'], <String>['query']);
      final d = productionToolDescriptors['search_knowledge'];
      expect(d, isNotNull);
      expect(d!.access, Access.read);
      expect(d.sideEffect, SideEffect.none);
    });

    test('rejects empty query', () async {
      final c = await seededMemory(const []);
      final out = await _invoke(c, tool, const {'query': '  '});
      expect(out['code'], 'bad_request');
    });

    test('returns cross-type results across sources', () async {
      final c = await seededMemory([
        mem('know:notes', 'n1', 'fire safety margin note'),
        mem('know:concepts', 'c1', 'fire safety margin concept'),
        mem('know:decisions', 'd1', 'unrelated grocery list'),
      ]);
      final out = await _invoke(c, tool, const {
        'query': 'fire safety margin',
        'top_k': 10,
      });
      final results = (out['results'] as List).cast<Object?>();
      final kinds = results.map((e) => (e as Map)['kind']).toSet();
      // Notes + concepts both indexed under the queried phrase show up.
      expect(kinds, containsAll(<String>['note', 'concept']));
    });

    test('types filter narrows to requested sources', () async {
      final c = await seededMemory([
        mem('know:notes', 'n1', 'alpha beta gamma'),
        mem('know:concepts', 'c1', 'alpha beta gamma'),
      ]);
      final out = await _invoke(c, tool, const {
        'query': 'alpha beta',
        'types': ['concept'],
      });
      final results = (out['results'] as List).cast<Object?>();
      expect(results.map((e) => (e as Map)['kind']).toSet(), {'concept'});
    });

    test('routine rows are searchable across the knowledge corpus', () async {
      final c = await seededMemory([
        mem('know:routines', 'r1', 'activate HK card every six months'),
      ]);
      final out = await _invoke(c, tool, const {
        'query': 'HK card active',
        'types': ['routine'],
      });
      final results = (out['results'] as List).cast<Object?>();
      expect(results.single as Map, containsPair('kind', 'routine'));
      expect(results.single as Map, containsPair('id', 'r1'));
    });

    test('skips stale memory rows without source objects', () async {
      final c = await seededMemory([
        mem('know:notes', 'missing', 'ghost note'),
      ], hydrate: false);
      final out = await _invoke(c, tool, const {'query': 'ghost note'});
      expect(out['results'], isEmpty);
    });
  });

  group('SearchNotesTool', () {
    const tool = SearchNotesTool();

    test(
      'falls back to hydrated Drift lexical search when memory is empty',
      () async {
        final db = makeTestDatabase();
        final repo = KnowledgeRepository(db: db, outbox: InMemoryOutboxStore());
        await repo.upsertNote(
          KnowledgeNote(
            id: 'n1',
            title: '港卡续期',
            bodyMd: '每 6 个月做一次活跃交易',
            tags: const ['hk'],
            projectTag: 'banking',
            createdAt: created,
            sync: meta(),
          ),
        );
        final rt = MemoryRuntime(
          embedder: StubEmbedder(),
          memoryStore: SqliteMemoryStore(db: db),
          eventStore: SqliteEventStore(db: db),
        );
        final c = ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(_prefs),
            memoryRuntimeProvider.overrideWith((ref) async => rt),
            knowledgeRepositoryProvider.overrideWith((ref) async => repo),
            currentUserIdProvider.overrideWithValue(() async => _owner),
          ],
        );
        addTearDown(c.dispose);
        addTearDown(db.close);

        final out = await _invoke(c, tool, const {
          'query': '港卡',
          'tags': ['hk'],
          'project': 'banking',
        });
        final notes = (out['notes'] as List).cast<Object?>();
        expect(notes.single as Map, containsPair('id', 'n1'));
        expect(notes.single as Map, contains('lexical_score'));
      },
    );
  });

  group('RecallDecisionTool', () {
    const tool = RecallDecisionTool();

    test('uses semantic memory then hydrates the decision source', () async {
      final db = makeTestDatabase();
      final repo = KnowledgeRepository(db: db, outbox: InMemoryOutboxStore());
      final decision = KnowledgeDecision(
        id: 'd1',
        question: '是否继续持有 NVDA?',
        options: const [],
        selectedLabel: '继续持有',
        rationaleMd: '长期 AI 需求仍然成立',
        principleIds: const [],
        assumptionIds: const [],
        status: DecisionStatus.active,
        decidedAt: created,
        sync: meta(),
      );
      await repo.upsertDecision(decision);
      final rt = MemoryRuntime(
        embedder: StubEmbedder(),
        memoryStore: SqliteMemoryStore(db: db),
        eventStore: SqliteEventStore(db: db),
      );
      await rt.remember(
        MemoryRecord(
          id: 'know:decisions:episodic:d1',
          kind: MemoryKind.episodic,
          ownerUserId: _owner,
          scope: '*',
          source: 'know:decisions',
          sourceId: 'd1',
          title: decision.question,
          summary: decision.rationaleMd,
          payload: const {},
          entities: const {},
          importance: 0.85,
          confidence: 0.9,
          createdAt: created,
          updatedAt: created,
        ),
      );
      final c = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(_prefs),
          memoryRuntimeProvider.overrideWith((ref) async => rt),
          knowledgeRepositoryProvider.overrideWith((ref) async => repo),
          currentUserIdProvider.overrideWithValue(() async => _owner),
        ],
      );
      addTearDown(c.dispose);
      addTearDown(db.close);

      final out = await _invoke(c, tool, const {'query': 'AI demand NVDA'});
      final decisions = (out['decisions'] as List).cast<Object?>();
      expect(decisions.single as Map, containsPair('id', 'd1'));
      expect(decisions.single as Map, contains('score'));
    });
  });

  group('ReviewKnowledgeHealthTool', () {
    const tool = ReviewKnowledgeHealthTool();

    Future<ProviderContainer> seededRepo(
      Future<void> Function(KnowledgeRepository repo) seed,
    ) async {
      final db = makeTestDatabase();
      final repo = KnowledgeRepository(db: db, outbox: InMemoryOutboxStore());
      await seed(repo);
      final c = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(_prefs),
          knowledgeRepositoryProvider.overrideWith((ref) async => repo),
          currentUserIdProvider.overrideWithValue(() async => _owner),
        ],
      );
      addTearDown(c.dispose);
      addTearDown(db.close);
      return c;
    }

    test('descriptor mirror match', () {
      expect(tool.name, 'review_knowledge_health');
      final d = productionToolDescriptors['review_knowledge_health'];
      expect(d, isNotNull);
      expect(d!.access, Access.read);
      expect(d.sideEffect, SideEffect.none);
    });

    test(
      'aggregates due reviews, due routines, stale assumptions, orphans',
      () async {
        final past = DateTime.utc(2020, 1, 1);
        final c = await seededRepo((repo) async {
          // Due decision (review_date in the past, status active).
          await repo.upsertDecision(
            KnowledgeDecision(
              id: 'dec1',
              question: '该不该满仓?',
              options: const [],
              selectedLabel: '',
              rationaleMd: '',
              principleIds: const [],
              assumptionIds: const [],
              status: DecisionStatus.active,
              reviewDate: past,
              decidedAt: past,
              sync: meta(),
            ),
          );
          // Due routine (next_due in the past).
          await repo.upsertRoutine(
            KnowledgeRoutine(
              id: 'r1',
              statement: '港卡活跃',
              intervalDays: 180,
              nextDueAt: past,
              scope: '*',
              status: RoutineStatus.active,
              createdAt: past,
              sync: meta(),
            ),
          );
          // Stale assumption (never verified).
          await repo.upsertAssumption(
            KnowledgeAssumption(
              id: 'a1',
              statement: '美股长期向上',
              confidence: 0.7,
              scope: '*',
              evidenceIds: const [],
              status: AssumptionStatus.active,
              declaredAt: past,
              sync: meta(),
            ),
          );
          // Orphan note (no tags, no project).
          await repo.upsertNote(
            KnowledgeNote(
              id: 'n1',
              title: '随手记',
              bodyMd: '',
              tags: const [],
              createdAt: created,
              sync: meta(),
            ),
          );
        });

        final out = await _invoke(c, tool, const {});
        expect(out['total_items'], 4);
        final sections = (out['sections'] as List).cast<Object?>();
        final byKey = {
          for (final s in sections)
            (s as Map)['key'] as String: s['count'] as int,
        };
        expect(byKey['due_reviews'], 1);
        expect(byKey['due_routines'], 1);
        expect(byKey['stale_assumptions'], 1);
        expect(byKey['orphan_notes'], 1);
      },
    );

    test('empty knowledge base reports zero with a note', () async {
      final c = await seededRepo((_) async {});
      final out = await _invoke(c, tool, const {});
      expect(out['total_items'], 0);
      expect(out['sections'], isEmpty);
      expect(out['note'], isNotNull);
    });
  });
}
