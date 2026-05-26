import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/contracts/memory_record.dart';
import 'package:naviwealth/core/ai/local/memory/memory_store.dart';

import '../../../../core/persistence/test_database.dart';

const _kFp = 'stub-v1-d2';
const _kOwner = 'u1';

DateTime _t(int day) => DateTime.utc(2026, 5, day);

MemoryRecord _mem({
  required String id,
  MemoryKind kind = MemoryKind.episodic,
  String scope = 'options_trading',
  String? source = 'options_trade_journal',
  String? sourceId,
  String title = 'NVDA put closed',
  String summary = 'closed at 70% credit',
  Map<String, Object?>? payload,
  Set<String> entities = const {'NVDA'},
  double importance = 0.6,
  double confidence = 0.8,
  DateTime? createdAt,
  DateTime? updatedAt,
  DateTime? validFrom,
  DateTime? validUntil,
}) => MemoryRecord(
  id: id,
  kind: kind,
  ownerUserId: _kOwner,
  scope: scope,
  source: source,
  sourceId: sourceId,
  title: title,
  summary: summary,
  payload: payload ?? const {'outcome': 'closed'},
  entities: entities,
  importance: importance,
  confidence: confidence,
  validFrom: validFrom,
  validUntil: validUntil,
  createdAt: createdAt ?? _t(1),
  updatedAt: updatedAt ?? _t(1),
);

void main() {
  late SqliteMemoryStore store;

  setUp(() {
    store = SqliteMemoryStore(db: makeTestDatabase());
  });

  group('SqliteMemoryStore CRUD', () {
    test('writeMemory + readMemory round-trips all typed fields', () async {
      await store.writeMemory(
        _mem(id: 'm1'),
        vector: const <double>[1, 0],
        fingerprint: _kFp,
      );
      final back = await store.readMemory('m1');
      expect(back, isNotNull);
      expect(back!.kind, MemoryKind.episodic);
      expect(back.scope, 'options_trading');
      expect(back.entities, {'NVDA'});
      expect(back.payload['outcome'], 'closed');
      expect(back.importance, closeTo(0.6, 1e-9));
    });

    test('writeMemory replaces both record and embedding', () async {
      await store.writeMemory(
        _mem(id: 'm1', title: 'v1'),
        vector: const <double>[1, 0],
        fingerprint: _kFp,
      );
      await store.writeMemory(
        _mem(id: 'm1', title: 'v2'),
        vector: const <double>[0, 1],
        fingerprint: _kFp,
      );
      expect(await store.countMemories(), 1);
      final back = await store.readMemory('m1');
      expect(back!.title, 'v2');
    });

    test('deleteMemory cascades to embedding (FK)', () async {
      await store.writeMemory(
        _mem(id: 'm1'),
        vector: const <double>[1, 0],
        fingerprint: _kFp,
      );
      await store.deleteMemory('m1');
      expect(await store.readMemory('m1'), isNull);
      expect(await store.countMemories(), 0);
    });

    test('writeMemoryWithoutVector stores record but no embedding', () async {
      await store.writeMemoryWithoutVector(_mem(id: 'rule-1'));
      final results = await store.queryMemories(
        ownerUserId: _kOwner,
        // No queryVector — embedding-less rows still come back.
      );
      expect(results, hasLength(1));
      expect(results.single.semanticSim, isNull);
    });

    test('touchAccess updates last_accessed_at', () async {
      await store.writeMemory(
        _mem(id: 'm1'),
        vector: const <double>[1, 0],
        fingerprint: _kFp,
      );
      final at = DateTime.utc(2026, 5, 20, 12);
      await store.touchAccess(['m1'], at);
      final back = await store.readMemory('m1');
      expect(back!.lastAccessedAt, at);
    });
  });

  group('SqliteMemoryStore.queryMemories', () {
    Future<void> seed() async {
      await store.writeMemory(
        _mem(id: 'a', kind: MemoryKind.episodic, entities: {'NVDA', 'put'}),
        vector: const <double>[1, 0],
        fingerprint: _kFp,
      );
      await store.writeMemory(
        _mem(id: 'b', kind: MemoryKind.episodic, entities: {'AAPL', 'call'}),
        vector: const <double>[0, 1],
        fingerprint: _kFp,
      );
      await store.writeMemoryWithoutVector(
        _mem(
          id: 'rule-1',
          kind: MemoryKind.procedural,
          scope: 'options_trading',
          title: 'close at 70%',
          summary: 'close any short put once 70% credit captured',
          entities: const {'put', 'cash_secured_put'},
          importance: 0.85,
        ),
      );
      await store.writeMemoryWithoutVector(
        _mem(
          id: 'pref-1',
          kind: MemoryKind.semantic,
          scope: '*',
          title: 'prefers local-first',
          summary: 'user values local-first systems',
          entities: const {},
          importance: 0.9,
        ),
      );
    }

    test('filters by kind', () async {
      await seed();
      final episodic = await store.queryMemories(
        ownerUserId: _kOwner,
        kinds: const {MemoryKind.episodic},
      );
      expect(episodic.map((c) => c.record.id), containsAll(['a', 'b']));
      expect(episodic.map((c) => c.record.id), isNot(contains('rule-1')));
    });

    test("scope filter: '*' records apply to any specific scope", () async {
      await seed();
      final scoped = await store.queryMemories(
        ownerUserId: _kOwner,
        scope: 'options_trading',
      );
      final ids = scoped.map((c) => c.record.id).toSet();
      // pref-1 is scope='*' — applies to every specific scope query.
      expect(ids, containsAll(['a', 'b', 'rule-1', 'pref-1']));
    });

    test("scope='*' query matches every scope", () async {
      await seed();
      final all = await store.queryMemories(ownerUserId: _kOwner, scope: '*');
      final ids = all.map((c) => c.record.id).toSet();
      expect(ids, containsAll(['a', 'b', 'rule-1', 'pref-1']));
    });

    test('mismatched specific scope excludes specific-scope records', () async {
      await seed();
      final scoped = await store.queryMemories(
        ownerUserId: _kOwner,
        scope: 'fire',
      );
      final ids = scoped.map((c) => c.record.id).toSet();
      // No 'fire'-scoped rows in the seed, but global pref still applies.
      expect(ids, contains('pref-1'));
      expect(ids, isNot(contains('a')));
      expect(ids, isNot(contains('rule-1')));
    });

    test('with queryVector + fingerprint scores by cosine', () async {
      await seed();
      final hits = await store.queryMemories(
        ownerUserId: _kOwner,
        kinds: const {MemoryKind.episodic},
        queryVector: const <double>[1, 0],
        fingerprint: _kFp,
      );
      hits.sort((a, b) => b.semanticSim!.compareTo(a.semanticSim!));
      expect(hits.first.record.id, 'a');
    });

    test('with queryVector but stale fingerprint returns nothing', () async {
      await seed();
      final hits = await store.queryMemories(
        ownerUserId: _kOwner,
        kinds: const {MemoryKind.episodic},
        queryVector: const <double>[1, 0],
        fingerprint: 'embeddinggemma-300m-onnx-int8-d768',
      );
      expect(hits, isEmpty);
    });

    test('validAt filters out expired memories', () async {
      await seed();
      await store.writeMemoryWithoutVector(
        _mem(
          id: 'expired-rule',
          kind: MemoryKind.procedural,
          validFrom: _t(1),
          validUntil: _t(5),
        ),
      );
      final at = _t(10);
      final live = await store.queryMemories(ownerUserId: _kOwner, validAt: at);
      expect(live.map((c) => c.record.id), isNot(contains('expired-rule')));
    });

    test('other owners are excluded', () async {
      await seed();
      final foreign = await store.queryMemories(ownerUserId: 'u2');
      expect(foreign, isEmpty);
    });
  });

  group('SqliteMemoryStore.dropOtherFingerprints', () {
    test('removes embeddings but leaves records', () async {
      await store.writeMemory(
        _mem(id: 'keep'),
        vector: const <double>[1, 0],
        fingerprint: _kFp,
      );
      await store.writeMemory(
        _mem(id: 'stale'),
        vector: const <double>[1, 0],
        fingerprint: 'stub-v0-d2',
      );
      final dropped = await store.dropOtherFingerprints(_kFp);
      expect(dropped, 1);
      // Both records still readable; the stale one just has no
      // embedding now and won't be returned for vector queries.
      expect(await store.readMemory('keep'), isNotNull);
      expect(await store.readMemory('stale'), isNotNull);
      final vectorHits = await store.queryMemories(
        ownerUserId: _kOwner,
        queryVector: const <double>[1, 0],
        fingerprint: _kFp,
      );
      expect(vectorHits.map((c) => c.record.id), ['keep']);
    });
  });

  group('packVector / unpackVector', () {
    test('Float32 roundtrip preserves to 1e-6', () {
      const v = <double>[1.0, -0.5, 0.25, 0.0];
      final back = unpackVector(packVector(v), v.length);
      for (var i = 0; i < v.length; i++) {
        expect(back[i], closeTo(v[i], 1e-6));
      }
    });
  });

  group('cosineSimilarity', () {
    test('identical → 1', () {
      expect(cosineSimilarity(const [1, 0], const [1, 0]), 1.0);
    });
    test('orthogonal → 0', () {
      expect(cosineSimilarity(const [1, 0], const [0, 1]), 0.0);
    });
    test('zero vector → 0', () {
      expect(cosineSimilarity(const [0, 0], const [1, 1]), 0.0);
    });
    test('shape mismatch → 0', () {
      expect(cosineSimilarity(const [1, 0], const [1, 0, 0]), 0.0);
    });
  });
}
