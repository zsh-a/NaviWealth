/// Local-only audit store for [AiTrace] records.
///
/// Traces NEVER replicate to the cloud (no OpLog, no D1) — they are a
/// privacy-transparency surface for the user, not a sync object. The
/// concrete storage backend is intentionally pluggable: Phase 1 uses
/// the in-memory ring buffer below; Phase 2 will introduce a Drift
/// table behind the same [AiTraceStore] interface.
library;

import '../contracts/contracts.dart';

abstract class AiTraceStore {
  /// Append a finalised trace. Implementations are expected to enforce
  /// retention (size or age) so this is a fire-and-forget call.
  Future<void> append(AiTrace trace);

  /// Most recent traces, newest first. `limit` caps the result; the
  /// store may return fewer rows.
  Future<List<AiTrace>> recent({int limit = 50});

  /// Drop traces whose `startedAtIso` is strictly before [cutoff].
  /// Callers schedule this — the store does not run cleanup itself.
  Future<void> pruneOlderThan(DateTime cutoff);
}

/// In-memory, ring-buffered [AiTraceStore] suitable for Phase 1.
///
/// State lives only for the current process — traces are lost on
/// restart. Phase 2 swaps this for a Drift-backed store with 30-day
/// rolling retention; until then the buffer is bounded by [maxSize]
/// so memory cannot grow unbounded.
class InMemoryAiTraceStore implements AiTraceStore {
  InMemoryAiTraceStore({this.maxSize = 500});

  final int maxSize;
  final List<AiTrace> _buffer = <AiTrace>[];

  @override
  Future<void> append(AiTrace trace) async {
    _buffer.add(trace);
    if (_buffer.length > maxSize) {
      _buffer.removeRange(0, _buffer.length - maxSize);
    }
  }

  @override
  Future<List<AiTrace>> recent({int limit = 50}) async {
    if (limit <= 0 || _buffer.isEmpty) return const <AiTrace>[];
    final clamped = limit > _buffer.length ? _buffer.length : limit;
    final start = _buffer.length - clamped;
    return _buffer.sublist(start).reversed.toList(growable: false);
  }

  @override
  Future<void> pruneOlderThan(DateTime cutoff) async {
    final cutoffIso = cutoff.toUtc().toIso8601String();
    _buffer.removeWhere((t) => t.startedAtIso.compareTo(cutoffIso) < 0);
  }

  /// Test-only escape hatch.
  int get debugLength => _buffer.length;
}
