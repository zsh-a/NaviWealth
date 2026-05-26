/// Riverpod wiring for the Memory Runtime
/// (`docs/lifeos-shell.md` §6, D-1.7b).
///
/// Domain-neutral — never imports `features/`. Feature-specific
/// extractors live next to the feature's data layer and are aggregated
/// by `app/memory_indexers_bootstrap.dart`.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/persistence/providers.dart';
import '../embedding/embedder.dart';
import 'context_builder.dart';
import 'event_store.dart';
import 'memory_runtime.dart';
import 'memory_store.dart';

/// The active embedder. Default is [StubEmbedder]; swap to the Rust
/// EmbeddingGemma port at bootstrap by overriding this provider with
/// a Future producing a [RustGemmaEmbedder].
///
/// Async because the Rust embedder's load is async (FRB-generated
/// `GemmaEmbedder.load` returns a `Future`). The stub default
/// completes synchronously for tests that don't override.
final embedderProvider = FutureProvider<Embedder>(
  (ref) async => StubEmbedder(),
);

final memoryStoreProvider = FutureProvider<MemoryStore>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  return SqliteMemoryStore(db: db);
});

final eventStoreProvider = FutureProvider<EventStore>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  return SqliteEventStore(db: db);
});

/// Single composition root for the Memory Runtime — every caller
/// (AI tools, indexers, UI) reads through this.
final memoryRuntimeProvider = FutureProvider<MemoryRuntime>((ref) async {
  final embedder = await ref.watch(embedderProvider.future);
  final memoryStore = await ref.watch(memoryStoreProvider.future);
  final eventStore = await ref.watch(eventStoreProvider.future);
  return MemoryRuntime(
    embedder: embedder,
    memoryStore: memoryStore,
    eventStore: eventStore,
  );
});

final contextBuilderProvider = FutureProvider<ContextBuilder>((ref) async {
  final runtime = await ref.watch(memoryRuntimeProvider.future);
  return ContextBuilder(runtime: runtime);
});
