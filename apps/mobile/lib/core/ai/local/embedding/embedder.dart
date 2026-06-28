/// Pure Dart embedding abstraction.
///
/// `StubEmbedder` is the deterministic hash-based pseudo-embedder used by
/// tests and dev builds. A real on-device embedder (EmbeddingGemma-300M
/// via Rust FFI + fastembed/ort — see `docs/architecture/lifeos-shell.md` §10) drops
/// in behind the same interface; the [Embedder.fingerprint] discipline
/// below lets the persistent vector store invalidate rows produced by
/// a different model.
library;

import 'dart:math' as math;

abstract class Embedder {
  /// Output vector dimension. Stable across calls.
  int get dimension;

  /// Stable identifier for this model + version + dimension. Persisted
  /// alongside every stored vector so the store can drop rows produced
  /// by a different embedder. Format is free-form but must change
  /// whenever the vector space changes (model swap, dimension change,
  /// normalisation rule change). Examples: `'stub-v1-d32'`,
  /// `'embeddinggemma-300m-onnx-int8-d768'`.
  String get fingerprint;

  /// Embed a single text. The returned vector has length [dimension]
  /// and is unit-length (L2-normalised) so consumers can use a plain
  /// dot product for similarity.
  Future<List<double>> embed(String text);
}

/// Convenience batch helper exposed as an extension so concrete
/// `implements Embedder` types don't need to re-implement it.
/// Concrete embedders that benefit from batched inference (a real
/// ONNX-backed model, when it lands) can add their own `embedAll`
/// method directly without hiding the extension.
extension EmbedderBatch on Embedder {
  Future<List<List<double>>> embedAll(Iterable<String> texts) async {
    final out = <List<double>>[];
    for (final t in texts) {
      out.add(await embed(t));
    }
    return out;
  }
}

/// Deterministic pseudo-embedder for tests + the 'no real model yet'
/// path. Same input → same vector across processes; close inputs
/// produce moderately close vectors (token-overlap collapses onto the
/// same hash bits).
///
/// Cosine quality is *not* great — this is not a substitute for a
/// real embedder. Tests verify ranking topology (the same string
/// always wins) rather than absolute similarity scores.
class StubEmbedder implements Embedder {
  StubEmbedder({this.dimension = 32});

  @override
  final int dimension;

  @override
  String get fingerprint => 'stub-v1-d$dimension';

  @override
  Future<List<double>> embed(String text) async {
    final v = List<double>.filled(dimension, 0);
    final tokens = text
        .toLowerCase()
        .split(RegExp(r'[\s\p{P}]+', unicode: true))
        .where((t) => t.isNotEmpty);
    for (final token in tokens) {
      final h = token.hashCode;
      for (var i = 0; i < dimension; i++) {
        // Map bit i of the hash to ±1 contribution at vector slot i.
        v[i] += ((h >> i) & 1) == 1 ? 1.0 : -1.0;
      }
    }
    return _normalise(v);
  }
}

List<double> _normalise(List<double> v) {
  var sumSq = 0.0;
  for (final x in v) {
    sumSq += x * x;
  }
  if (sumSq == 0) return v;
  final norm = math.sqrt(sumSq);
  return <double>[for (final x in v) x / norm];
}
