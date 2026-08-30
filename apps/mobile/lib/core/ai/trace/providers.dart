/// Riverpod surface for the AI trace store.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../core/persistence/providers.dart';
import '../contracts/contracts.dart';
import 'ai_trace_store.dart';
import 'drift_ai_trace_store.dart';

final _aiTraceRevisionProvider = StateProvider<int>((_) => 0);

/// Backend storage for [AiTrace] records.
///
/// Production wiring: falls back to in-memory until the
/// Drift database is ready, then switches to the Drift-backed store.
/// The async DB boot is one-shot — once available we keep the same
/// store instance for the rest of the session.
///
/// Tests / dev: override this provider with a hand-rolled
/// `InMemoryAiTraceStore` to keep tests fast and hermetic.
final Provider<AiTraceStore> aiTraceStoreProvider = Provider<AiTraceStore>((
  ref,
) {
  final dbAsync = ref.watch(appDatabaseProvider);
  final store = dbAsync.when(
    data: (db) => DriftAiTraceStore(db),
    // Until the DB is open, traces buffer in memory; once the DB
    // becomes available callers re-watch this provider and the in-memory
    // buffer is dropped (it was only filled during boot — typically a
    // sub-second window).
    loading: () => InMemoryAiTraceStore(),
    error: (_, _) => InMemoryAiTraceStore(),
  );
  return _RefreshingAiTraceStore(
    store,
    onAppend: (_) => ref.read(_aiTraceRevisionProvider.notifier).state++,
  );
});

/// Most-recent traces (newest first). UI surfaces should depend on
/// this provider; refresh by invalidating it after a write.
final recentAiTracesProvider = FutureProvider.autoDispose<List<AiTrace>>((ref) {
  ref.watch(_aiTraceRevisionProvider);
  return ref.watch(aiTraceStoreProvider).recent();
});

/// Per-message lookup keyed by `AiTrace.requestId`. The chat surface
/// uses `ChatMessage.id == requestId`, so any consumer can resolve the
/// trace for a message directly. Auto-disposed because trace lookups
/// are typically per-card and short-lived.
final aiTraceByIdProvider = FutureProvider.autoDispose.family<AiTrace?, String>(
  (ref, requestId) {
    ref.watch(_aiTraceRevisionProvider);
    return ref.watch(aiTraceStoreProvider).findByRequestId(requestId);
  },
);

class _RefreshingAiTraceStore implements AiTraceStore {
  const _RefreshingAiTraceStore(this._delegate, {required this.onAppend});

  final AiTraceStore _delegate;
  final void Function(AiTrace trace) onAppend;

  @override
  Future<void> append(AiTrace trace) async {
    await _delegate.append(trace);
    onAppend(trace);
  }

  @override
  Future<AiTrace?> findByRequestId(String requestId) =>
      _delegate.findByRequestId(requestId);

  @override
  Future<void> pruneOlderThan(DateTime cutoff) =>
      _delegate.pruneOlderThan(cutoff);

  @override
  Future<List<AiTrace>> recent({int limit = 50}) =>
      _delegate.recent(limit: limit);
}
