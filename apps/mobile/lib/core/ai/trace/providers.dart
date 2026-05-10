/// Riverpod surface for the AI trace store.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../contracts/contracts.dart';
import 'ai_trace_store.dart';

/// Backend storage for [AiTrace] records. Default is the in-memory
/// ring buffer — overridden in tests, and swapped for a Drift impl in
/// Phase 2 via `ProviderContainer.overrides`.
final aiTraceStoreProvider = Provider<AiTraceStore>(
  (ref) => InMemoryAiTraceStore(),
);

/// Most-recent traces (newest first). UI surfaces should depend on
/// this provider; refresh by invalidating it after a write.
final recentAiTracesProvider = FutureProvider<List<AiTrace>>(
  (ref) => ref.watch(aiTraceStoreProvider).recent(),
);

/// Per-message lookup keyed by `AiTrace.requestId`. The chat surface
/// uses `ChatMessage.id == requestId`, so any consumer can resolve the
/// trace for a message directly. Auto-disposed because trace lookups
/// are typically per-card and short-lived.
final aiTraceByIdProvider = FutureProvider.autoDispose
    .family<AiTrace?, String>(
      (ref, requestId) =>
          ref.watch(aiTraceStoreProvider).findByRequestId(requestId),
    );
