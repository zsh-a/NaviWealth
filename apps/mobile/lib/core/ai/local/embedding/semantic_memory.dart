/// User-facing wrapper over [Embedder] + [VectorStore].
///
/// Plays the same role as the contracts' `SemanticHit` placeholder:
/// transactions notes, manually-entered memos, scanned documents,
/// tag descriptions all become memory entries the cloud planner can
/// receive (at most top-K) inside [TaskContext.retrieved].
library;

import '../../contracts/contracts.dart' show SemanticHit;
import 'embedder.dart';
import 'vector_store.dart';

class SemanticMemory {
  const SemanticMemory({required this.embedder, required this.store});

  final Embedder embedder;
  final VectorStore store;

  /// Embed and store one entry. Replaces the prior entry for [id]
  /// if any. The embedded text is `'$title\n$body'` so the title
  /// gets weight even when the body is long.
  Future<void> remember({
    required String id,
    required String source,
    required String title,
    required String body,
  }) async {
    final vec = await embedder.embed('$title\n$body');
    await store.upsert(
      StoredDocument(
        id: id,
        source: source,
        title: title,
        body: body,
        vector: vec,
      ),
    );
  }

  Future<void> forget(String id) => store.remove(id);

  /// Embed [query], retrieve top-K, return [SemanticHit]s with a
  /// short excerpt centred on the query (substring window — good
  /// enough until Phase 5 adds a smarter chunker).
  Future<List<SemanticHit>> search(String query, {int topK = 5}) async {
    final qvec = await embedder.embed(query);
    final hits = await store.search(qvec, topK: topK);
    return <SemanticHit>[
      for (final h in hits)
        SemanticHit(
          source: h.doc.source,
          title: h.doc.title,
          excerpt: _excerptAround(h.doc.body, query),
          score: h.score,
        ),
    ];
  }

  Future<int> get size => store.count();
}

/// 80-char window around the first occurrence of [query] in [body];
/// falls back to the body's prefix when there's no overlap. Public
/// for tests.
String excerptAround(String body, String query) =>
    _excerptAround(body, query);

String _excerptAround(String body, String query) {
  if (body.isEmpty) return '';
  final lb = body.toLowerCase();
  final lq = query.toLowerCase();
  final idx = lq.isEmpty ? -1 : lb.indexOf(lq);
  const window = 80;
  if (idx < 0) {
    return body.length <= window ? body : '${body.substring(0, window)}…';
  }
  final start = (idx - 20).clamp(0, body.length);
  final end = (start + window).clamp(0, body.length);
  var slice = body.substring(start, end);
  if (start > 0) slice = '…$slice';
  if (end < body.length) slice = '$slice…';
  return slice;
}
