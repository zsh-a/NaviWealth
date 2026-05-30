/// User-facing Memory Runtime (`docs/lifeos-shell.md` §6, D-1.7b).
///
/// Composes [Embedder] + [MemoryStore] + [EventStore]. Per-feature
/// extractors call [remember] / [recordEvent]; the agent's
/// [ContextBuilder] calls [recall] / [recentEvents]; UI / settings
/// call [forget] / [supersede].
///
/// Cross-domain neutral — no Finance / Health-specific types. New
/// domains plug in by writing their own extractor that hands
/// [MemoryRecord]s through this surface.
library;

import '../../contracts/event_record.dart';
import '../../contracts/memory_record.dart';
import '../embedding/embedder.dart';
import 'event_store.dart';
import 'hybrid_scorer.dart';
import 'memory_store.dart';

/// A single ranked memory hit, returned by [MemoryRuntime.recall]. The
/// caller decides which sub-scores to surface.
class MemoryHit {
  const MemoryHit({
    required this.record,
    required this.score,
    required this.semanticSim,
    required this.entityOverlap,
    required this.recency,
  });

  final MemoryRecord record;
  final double score;
  final double? semanticSim;
  final double entityOverlap;
  final double recency;
}

class MemoryRuntime {
  MemoryRuntime({
    required this.embedder,
    required this.memoryStore,
    required this.eventStore,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Embedder embedder;
  final MemoryStore memoryStore;
  final EventStore eventStore;
  final DateTime Function() _clock;

  /// Persist [record] + its embedding. Title + summary are embedded
  /// jointly so the title carries weight even when the summary is
  /// long.
  ///
  /// Idempotent: re-calling with the same [record.id] overwrites both
  /// the record and the embedding.
  Future<void> remember(MemoryRecord record) async {
    final vec = await embedder.embed('${record.title}\n${record.summary}');
    await memoryStore.writeMemory(
      record,
      vector: vec,
      fingerprint: embedder.fingerprint,
    );
  }

  /// Persist [record] without an embedding. Use for memories the user
  /// will only look up by kind / scope / entity (e.g. settings-defined
  /// procedural rules) or where the embedding isn't useful yet.
  Future<void> rememberWithoutEmbedding(MemoryRecord record) =>
      memoryStore.writeMemoryWithoutVector(record);

  Future<void> forget(String id) => memoryStore.deleteMemory(id);

  /// Keep the derived memory rows for one domain source in sync with its
  /// live source ids. Source tables are authoritative; memory rows are an
  /// index and should disappear when a source row is soft-deleted or merged.
  Future<void> forgetSourceExcept({
    required String ownerUserId,
    required String source,
    required Set<String> keepSourceIds,
  }) => memoryStore.deleteMemoriesBySourceExcept(
    ownerUserId: ownerUserId,
    source: source,
    keepSourceIds: keepSourceIds,
  );

  /// Mark [oldId] as ending now and write [newRecord] (typically with
  /// `validFrom = now`). Use to evolve a preference / rule without
  /// losing the prior version's history.
  Future<void> supersede(String oldId, MemoryRecord newRecord) async {
    final prior = await memoryStore.readMemory(oldId);
    if (prior != null) {
      final now = _clock();
      await memoryStore.writeMemoryWithoutVector(
        prior.copyWith(validUntil: now, updatedAt: now),
      );
    }
    await remember(newRecord);
  }

  /// Hybrid-scored recall.
  ///
  /// - [queryText] supplied → semantic similarity contributes
  /// - [entityFilter] supplied → entity overlap contributes
  /// - [kinds] / [scope] / [source] / [validAt] are hard filters
  /// - Result is sorted by hybrid score desc and cut to [topK]
  ///
  /// Touches `last_accessed_at` on the returned ids as a side effect
  /// (drives LRU recency).
  Future<List<MemoryHit>> recall({
    required String ownerUserId,
    String? queryText,
    Set<String>? entityFilter,
    Set<MemoryKind>? kinds,
    String? scope,
    String? source,
    DateTime? validAt,
    int topK = 10,
    Duration recencyHalfLife = const Duration(days: 30),
  }) async {
    if (topK <= 0) return const <MemoryHit>[];
    final now = _clock();

    List<double>? queryVec;
    String? fingerprint;
    if (queryText != null && queryText.trim().isNotEmpty) {
      queryVec = await embedder.embed(queryText.trim());
      fingerprint = embedder.fingerprint;
    }

    final candidates = await memoryStore.queryMemories(
      ownerUserId: ownerUserId,
      kinds: kinds,
      scope: scope,
      source: source,
      queryVector: queryVec,
      fingerprint: fingerprint,
      validAt: validAt ?? now,
      limit: topK,
    );
    if (candidates.isEmpty) return const <MemoryHit>[];

    final hits = <MemoryHit>[];
    for (final c in candidates) {
      final ent = (entityFilter == null || entityFilter.isEmpty)
          ? 0.0
          : entityOverlap(c.record.entities, entityFilter);
      final rec = recencyScore(
        c.record.updatedAt,
        now,
        halfLife: recencyHalfLife,
      );
      final score = hybridScore(
        semanticSim: c.semanticSim,
        importance: c.record.importance,
        entityOverlap: ent,
        recency: rec,
        confidence: c.record.confidence,
      );
      hits.add(
        MemoryHit(
          record: c.record,
          score: score,
          semanticSim: c.semanticSim,
          entityOverlap: ent,
          recency: rec,
        ),
      );
    }
    hits.sort((a, b) => b.score.compareTo(a.score));
    final cut = hits.length <= topK ? hits : hits.sublist(0, topK);

    // Update access timestamps (best-effort fire-and-forget would be
    // racy with tests; await but ignore failures).
    await memoryStore.touchAccess(cut.map((h) => h.record.id), now);

    return cut;
  }

  /// Append an event to the cross-domain log. Idempotent by id.
  Future<void> recordEvent(EventRecord event) => eventStore.writeEvent(event);

  Future<List<EventRecord>> recentEvents({
    required String ownerUserId,
    String? source,
    Set<String>? typeFilter,
    Set<String>? entityFilter,
    Duration window = const Duration(days: 30),
    int limit = 50,
  }) => eventStore.recentEvents(
    ownerUserId: ownerUserId,
    source: source,
    typeFilter: typeFilter,
    entityFilter: entityFilter,
    since: _clock().subtract(window),
    limit: limit,
  );

  /// Drop every embedding whose fingerprint != current embedder's.
  /// Call after swapping the embedder (e.g. Stub → Rust EmbeddingGemma);
  /// the next indexer cycle re-embeds with the new model.
  Future<int> dropStaleVectors() =>
      memoryStore.dropOtherFingerprints(embedder.fingerprint);

  Future<int> get memoryCount => memoryStore.countMemories();
  Future<int> get eventCount => eventStore.countEvents();
}
