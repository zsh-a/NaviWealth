/// Tiny vector index abstraction.
///
/// Today only [InMemoryVectorStore] exists — linear scan, fine up to a
/// few thousand docs but not persistent. A sqlite-vec or HNSW-backed
/// implementation can drop in behind the same interface; the model
/// fingerprint discipline (see [StoredDocument.vector]) is still
/// stub-grade and must tighten before swapping in a persistent store.
library;

import 'dart:math' as math;

class StoredDocument {
  const StoredDocument({
    required this.id,
    required this.source,
    required this.title,
    required this.body,
    required this.vector,
  });

  final String id;

  /// Coarse classification ('note', 'transaction', 'document', 'tag').
  /// Surfaced back into [SemanticHit.source] so downstream UI can
  /// route results by kind.
  final String source;

  final String title;
  final String body;

  /// L2-normalised embedding produced by the active [Embedder]. The
  /// store treats it opaquely — there is no model fingerprint check
  /// today because only one embedder exists; a fingerprint must be
  /// added before a real embedder ships (see `docs/ai-boundary-audit.md`
  /// §3.1).
  final List<double> vector;
}

class SearchHit {
  const SearchHit({required this.doc, required this.score});

  final StoredDocument doc;

  /// Cosine similarity in `[-1, 1]` (in practice `[0, 1]` for the
  /// stub embedder). Higher = more similar.
  final double score;
}

abstract class VectorStore {
  Future<void> upsert(StoredDocument doc);
  Future<void> remove(String id);
  Future<List<SearchHit>> search(List<double> query, {int topK = 5});
  Future<int> count();
}

class InMemoryVectorStore implements VectorStore {
  final List<StoredDocument> _docs = <StoredDocument>[];

  @override
  Future<void> upsert(StoredDocument doc) async {
    final idx = _docs.indexWhere((d) => d.id == doc.id);
    if (idx >= 0) {
      _docs[idx] = doc;
    } else {
      _docs.add(doc);
    }
  }

  @override
  Future<void> remove(String id) async {
    _docs.removeWhere((d) => d.id == id);
  }

  @override
  Future<List<SearchHit>> search(List<double> query, {int topK = 5}) async {
    if (_docs.isEmpty || topK <= 0) return const <SearchHit>[];
    final hits = <SearchHit>[
      for (final d in _docs)
        SearchHit(doc: d, score: cosineSimilarity(query, d.vector)),
    ]..sort((a, b) => b.score.compareTo(a.score));
    return hits.take(topK).toList(growable: false);
  }

  @override
  Future<int> count() async => _docs.length;
}

/// Pure cosine similarity. Tolerates non-normalised inputs (computes
/// magnitude on the fly); returns `0` when either side has zero
/// magnitude. Exposed for tests and for the alternative store impls
/// that may want to share the math.
double cosineSimilarity(List<double> a, List<double> b) {
  if (a.length != b.length) return 0;
  var dot = 0.0;
  var sa = 0.0;
  var sb = 0.0;
  for (var i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    sa += a[i] * a[i];
    sb += b[i] * b[i];
  }
  if (sa == 0 || sb == 0) return 0;
  return dot / (math.sqrt(sa) * math.sqrt(sb));
}
