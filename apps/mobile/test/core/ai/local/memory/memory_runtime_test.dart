import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/contracts/event_record.dart';
import 'package:naviwealth/core/ai/contracts/memory_record.dart';
import 'package:naviwealth/core/ai/local/embedding/embedder.dart';
import 'package:naviwealth/core/ai/local/memory/event_store.dart';
import 'package:naviwealth/core/ai/local/memory/memory_runtime.dart';
import 'package:naviwealth/core/ai/local/memory/memory_store.dart';

import '../../../../core/persistence/test_database.dart';

const _kOwner = 'u1';

MemoryRecord _mem({
  required String id,
  MemoryKind kind = MemoryKind.episodic,
  String scope = 'options_trading',
  String source = 'test',
  String? sourceId,
  String title = '',
  String summary = '',
  Set<String> entities = const {},
  double importance = 0.6,
  double confidence = 0.85,
  DateTime? at,
}) {
  final t = at ?? DateTime.utc(2026, 5, 24);
  return MemoryRecord(
    id: id,
    kind: kind,
    ownerUserId: _kOwner,
    scope: scope,
    source: source,
    sourceId: sourceId,
    title: title.isEmpty ? id : title,
    summary: summary.isEmpty ? 'summary $id' : summary,
    payload: const {},
    entities: entities,
    importance: importance,
    confidence: confidence,
    createdAt: t,
    updatedAt: t,
  );
}

MemoryRuntime _runtime({DateTime Function()? clock}) {
  final db = makeTestDatabase();
  return MemoryRuntime(
    embedder: StubEmbedder(),
    memoryStore: SqliteMemoryStore(db: db),
    eventStore: SqliteEventStore(db: db),
    clock: clock,
  );
}

void main() {
  group('MemoryRuntime.remember + recall', () {
    test('semantic recall ranks the exact-match doc first', () async {
      final rt = _runtime();
      await rt.remember(
        _mem(
          id: 'a',
          title: 'renovation budget',
          summary: 'renovation renovation budget renovation costs',
        ),
      );
      await rt.remember(
        _mem(
          id: 'b',
          title: 'subscriptions',
          summary: 'netflix spotify subscription monthly',
        ),
      );
      final hits = await rt.recall(
        ownerUserId: _kOwner,
        queryText: 'renovation',
        topK: 3,
      );
      expect(hits, isNotEmpty);
      expect(hits.first.record.id, 'a');
    });

    test('entity overlap boosts identical-text records', () async {
      final rt = _runtime();
      await rt.remember(
        _mem(id: 'matched', summary: 'short put', entities: const {'NVDA'}),
      );
      await rt.remember(
        _mem(id: 'unmatched', summary: 'short put', entities: const {'AAPL'}),
      );
      final hits = await rt.recall(
        ownerUserId: _kOwner,
        queryText: 'short put',
        entityFilter: const {'NVDA'},
      );
      expect(hits.first.record.id, 'matched');
    });

    test('importance breaks ties when other signals are equal', () async {
      final rt = _runtime();
      await rt.remember(_mem(id: 'high', summary: 'sample', importance: 0.9));
      await rt.remember(_mem(id: 'low', summary: 'sample', importance: 0.2));
      final hits = await rt.recall(ownerUserId: _kOwner, queryText: 'sample');
      expect(hits.first.record.id, 'high');
    });

    test('owner isolation', () async {
      final rt = _runtime();
      await rt.remember(_mem(id: 'mine', summary: 'starbucks'));
      // Hand-craft a record for a different owner.
      await rt.remember(
        MemoryRecord(
          id: 'theirs',
          kind: MemoryKind.episodic,
          ownerUserId: 'u2',
          title: 'theirs',
          summary: 'starbucks',
          payload: const {},
          entities: const {},
          importance: 0.5,
          confidence: 0.8,
          createdAt: DateTime.utc(2026, 5, 24),
          updatedAt: DateTime.utc(2026, 5, 24),
        ),
      );
      final hits = await rt.recall(
        ownerUserId: _kOwner,
        queryText: 'starbucks',
      );
      expect(hits.map((h) => h.record.id), ['mine']);
    });

    test('recall touches last_accessed_at on hits', () async {
      final fixed = DateTime.utc(2026, 5, 24, 12);
      final rt = _runtime(clock: () => fixed);
      await rt.remember(_mem(id: 'a', at: DateTime.utc(2026, 5, 1)));
      await rt.recall(ownerUserId: _kOwner, queryText: 'summary a');
      final back = await rt.memoryStore.readMemory('a');
      expect(back!.lastAccessedAt, fixed);
    });
  });

  group('MemoryRuntime.forget + supersede', () {
    test('forget removes the record', () async {
      final rt = _runtime();
      await rt.remember(_mem(id: 'a'));
      await rt.forget('a');
      expect(await rt.memoryCount, 0);
    });

    test('forgetSourceExcept prunes stale derived rows by sourceId', () async {
      final rt = _runtime();
      await rt.remember(_mem(id: 'keep', source: 'know:notes', sourceId: 'n1'));
      await rt.remember(_mem(id: 'drop', source: 'know:notes', sourceId: 'n2'));
      await rt.remember(
        _mem(id: 'other', source: 'know:concepts', sourceId: 'c1'),
      );

      await rt.forgetSourceExcept(
        ownerUserId: _kOwner,
        source: 'know:notes',
        keepSourceIds: const {'n1'},
      );

      expect(await rt.memoryStore.readMemory('keep'), isNotNull);
      expect(await rt.memoryStore.readMemory('drop'), isNull);
      expect(await rt.memoryStore.readMemory('other'), isNotNull);
    });

    test(
      'supersede stamps validUntil on the old record + writes new',
      () async {
        final now = DateTime.utc(2026, 6, 1);
        final rt = _runtime(clock: () => now);
        await rt.remember(
          _mem(
            id: 'old-pref',
            kind: MemoryKind.semantic,
            title: 'prefers SaaS',
          ),
        );
        await rt.supersede(
          'old-pref',
          _mem(
            id: 'new-pref',
            kind: MemoryKind.semantic,
            title: 'prefers local-first',
          ),
        );
        final old = await rt.memoryStore.readMemory('old-pref');
        expect(old!.validUntil, now);
        final created = await rt.memoryStore.readMemory('new-pref');
        expect(created, isNotNull);
      },
    );
  });

  group('MemoryRuntime.recordEvent + recentEvents', () {
    test('events come back desc by timestamp + filtered by entity', () async {
      final fixed = DateTime.utc(2026, 5, 24, 12);
      final rt = _runtime(clock: () => fixed);
      await rt.recordEvent(
        EventRecord(
          id: 'e1',
          type: 'trade_closed',
          timestamp: DateTime.utc(2026, 5, 20),
          source: 'options_trade_journal',
          ownerUserId: _kOwner,
          summary: 'closed NVDA',
          payload: const {},
          entities: const {'NVDA'},
        ),
      );
      await rt.recordEvent(
        EventRecord(
          id: 'e2',
          type: 'trade_closed',
          timestamp: DateTime.utc(2026, 5, 22),
          source: 'options_trade_journal',
          ownerUserId: _kOwner,
          summary: 'closed AAPL',
          payload: const {},
          entities: const {'AAPL'},
        ),
      );
      final all = await rt.recentEvents(ownerUserId: _kOwner);
      expect(all.map((e) => e.id), ['e2', 'e1']);
      final nvdaOnly = await rt.recentEvents(
        ownerUserId: _kOwner,
        entityFilter: const {'NVDA'},
      );
      expect(nvdaOnly.map((e) => e.id), ['e1']);
    });
  });

  group('MemoryRuntime.dropStaleVectors', () {
    test('drops embeddings whose fingerprint != current', () async {
      final rt = _runtime();
      // Write one through the runtime (current fingerprint).
      await rt.remember(_mem(id: 'fresh'));
      // Sneak in a stale-fingerprint row directly.
      await rt.memoryStore.writeMemory(
        _mem(id: 'stale'),
        vector: const [1, 0],
        fingerprint: 'stub-v0-d2',
      );
      final dropped = await rt.dropStaleVectors();
      expect(dropped, 1);
      // Records survive; only embeddings dropped.
      expect(await rt.memoryCount, 2);
    });
  });
}
