import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/local/embedding/embedding.dart';

void main() {
  group('StubEmbedder', () {
    test('deterministic: same text → same vector', () async {
      final e = StubEmbedder();
      final v1 = await e.embed('上月在星巴克买了咖啡');
      final v2 = await e.embed('上月在星巴克买了咖啡');
      expect(v1, v2);
    });

    test('returns the configured dimension', () async {
      final e = StubEmbedder(dimension: 16);
      final v = await e.embed('hello world');
      expect(v, hasLength(16));
    });

    test('output is approximately unit length', () async {
      final e = StubEmbedder();
      final v = await e.embed('subscription netflix monthly');
      final mag = _magnitude(v);
      expect(mag, closeTo(1.0, 1e-9));
    });
  });

  group('cosineSimilarity', () {
    test('identical vectors → 1', () {
      expect(cosineSimilarity(<double>[1, 0, 0], <double>[1, 0, 0]), 1);
    });

    test('orthogonal vectors → 0', () {
      expect(cosineSimilarity(<double>[1, 0], <double>[0, 1]), 0);
    });

    test('zero vector → 0 (no NaN)', () {
      expect(cosineSimilarity(<double>[0, 0], <double>[1, 1]), 0);
    });

    test('dimension mismatch → 0', () {
      expect(cosineSimilarity(<double>[1, 0], <double>[1, 0, 0]), 0);
    });
  });

  group('InMemoryVectorStore', () {
    test('upsert + search returns top-K by score', () async {
      final store = InMemoryVectorStore();
      await store.upsert(
        const StoredDocument(
          id: 'a',
          source: 'note',
          title: 'A',
          body: '',
          vector: <double>[1, 0, 0],
        ),
      );
      await store.upsert(
        const StoredDocument(
          id: 'b',
          source: 'note',
          title: 'B',
          body: '',
          vector: <double>[0, 1, 0],
        ),
      );
      await store.upsert(
        const StoredDocument(
          id: 'c',
          source: 'note',
          title: 'C',
          body: '',
          vector: <double>[0.9, 0.1, 0],
        ),
      );

      final hits = await store.search(const <double>[1, 0, 0], topK: 2);
      expect(hits, hasLength(2));
      expect(hits[0].doc.id, 'a');
      expect(hits[1].doc.id, 'c');
    });

    test('upsert by same id replaces in place', () async {
      final store = InMemoryVectorStore();
      await store.upsert(
        const StoredDocument(
          id: 'x',
          source: 'note',
          title: 'old',
          body: '',
          vector: <double>[1, 0],
        ),
      );
      await store.upsert(
        const StoredDocument(
          id: 'x',
          source: 'note',
          title: 'new',
          body: '',
          vector: <double>[1, 0],
        ),
      );
      expect(await store.count(), 1);
      final hits = await store.search(const <double>[1, 0]);
      expect(hits.single.doc.title, 'new');
    });

    test('remove drops the entry', () async {
      final store = InMemoryVectorStore();
      await store.upsert(
        const StoredDocument(
          id: 'x',
          source: 'note',
          title: 't',
          body: '',
          vector: <double>[1, 0],
        ),
      );
      await store.remove('x');
      expect(await store.count(), 0);
    });

    test('topK <= 0 returns empty', () async {
      final store = InMemoryVectorStore();
      await store.upsert(
        const StoredDocument(
          id: 'x',
          source: 'note',
          title: 't',
          body: '',
          vector: <double>[1, 0],
        ),
      );
      expect(await store.search(const <double>[1, 0], topK: 0), isEmpty);
    });
  });

  group('SemanticMemory', () {
    test('remember + search ranks the exact-match doc first', () async {
      // Token-level overlap is the only signal the stub embedder
      // tracks (its hash-bit weights are uncorrelated with semantic
      // proximity), so we exercise ranking via clean repeated tokens
      // and verify only the top hit. Phase 5's real embedder lifts
      // this to semantic ranking.
      final mem = SemanticMemory(
        embedder: StubEmbedder(),
        store: InMemoryVectorStore(),
      );
      await mem.remember(
        id: 'doc_1',
        source: 'note',
        title: 'renovation',
        body: 'renovation renovation budget renovation costs',
      );
      await mem.remember(
        id: 'doc_2',
        source: 'note',
        title: 'subscriptions',
        body: 'netflix spotify subscription monthly',
      );
      await mem.remember(
        id: 'doc_3',
        source: 'note',
        title: 'travel notes',
        body: 'flight and hotel for upcoming trip',
      );

      final hits = await mem.search('renovation', topK: 3);
      expect(hits, hasLength(3));
      expect(hits.first.title, 'renovation');
      expect(hits.first.excerpt, contains('renovation'));
    });

    test('search results carry the document source through', () async {
      final mem = SemanticMemory(
        embedder: StubEmbedder(),
        store: InMemoryVectorStore(),
      );
      await mem.remember(
        id: 'n1',
        source: 'transaction',
        title: 'starbucks',
        body: 'coffee at starbucks',
      );
      final hits = await mem.search('starbucks', topK: 1);
      expect(hits.single.source, 'transaction');
    });

    test('forget removes from memory', () async {
      final mem = SemanticMemory(
        embedder: StubEmbedder(),
        store: InMemoryVectorStore(),
      );
      await mem.remember(
        id: 'doc_1',
        source: 'note',
        title: 'a',
        body: 'b',
      );
      expect(await mem.size, 1);
      await mem.forget('doc_1');
      expect(await mem.size, 0);
    });

    test('excerptAround returns prefix when query is absent', () {
      final out = excerptAround('hello world this is a body text', 'unrelated');
      expect(out, startsWith('hello world'));
    });

    test('excerptAround centres on the query match', () {
      const body = '前面是一些铺垫文字……然后用户提到 装修 花费，再后面是其他内容';
      final out = excerptAround(body, '装修');
      expect(out, contains('装修'));
    });
  });
}

double _magnitude(List<double> v) {
  var s = 0.0;
  for (final x in v) {
    s += x * x;
  }
  return math.sqrt(s);
}
