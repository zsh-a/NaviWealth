/// Context Builder (`docs/architecture/lifeos-shell.md` §6, D-1.7b).
///
/// Assembles a [ContextPackMemory] for one agent turn by drawing from
/// the four memory kinds + the recent event log. The pack is the
/// LLM-facing shape — the LLM doesn't re-classify what it gets.
///
/// Slot assembly rules:
///
/// | slot               | source                            | filter                                                   |
/// |--------------------|-----------------------------------|----------------------------------------------------------|
/// | user_preferences   | `MemoryKind.semantic` recall      | scope match, no semantic query (preferences are stable)  |
/// | applicable_rules   | `MemoryKind.procedural` recall    | scope match, no semantic query (rules are explicit)      |
/// | related_decisions  | `MemoryKind.episodic` recall      | hybrid-scored by intent.freeText + entities              |
/// | recent_events      | `EventStore.recentEvents`         | owner + time window                                      |
/// | related_events     | same as recent_events             | filtered by intent entities                              |
library;

import '../../contracts/context_pack_memory.dart';
import '../../contracts/event_record.dart';
import '../../contracts/memory_record.dart';
import 'memory_runtime.dart' show MemoryHit, MemoryRuntime;

class ContextBuilder {
  ContextBuilder({required this.runtime});

  final MemoryRuntime runtime;

  /// Build the pack for [ownerUserId] given [intent]. All slots are
  /// bounded by [perSlotLimit] to keep prompt cost predictable. The
  /// caller can override per-slot limits via [Limits].
  Future<ContextPackMemory> build({
    required String ownerUserId,
    required ContextIntent intent,
    int perSlotLimit = 6,
    Duration eventWindow = const Duration(days: 30),
  }) async {
    final scope = intent.scope;
    final entities = intent.entities.isEmpty ? null : intent.entities;

    // Semantic preferences — no semantic query needed; the user's
    // long-term facts should always come through when in-scope.
    final preferences =
        intent.kindHints.isEmpty ||
            intent.kindHints.contains(MemoryKind.semantic)
        ? await runtime.recall(
            ownerUserId: ownerUserId,
            kinds: const {MemoryKind.semantic},
            scope: scope,
            entityFilter: entities,
            topK: perSlotLimit,
          )
        : const <MemoryHit>[];

    // Procedural rules — explicit; embed scope-match only.
    final rules =
        intent.kindHints.isEmpty ||
            intent.kindHints.contains(MemoryKind.procedural)
        ? await runtime.recall(
            ownerUserId: ownerUserId,
            kinds: const {MemoryKind.procedural},
            scope: scope,
            entityFilter: entities,
            topK: perSlotLimit,
          )
        : const <MemoryHit>[];

    // Episodic decisions — hybrid-scored against intent.
    final episodicHits =
        intent.kindHints.isEmpty ||
            intent.kindHints.contains(MemoryKind.episodic)
        ? await runtime.recall(
            ownerUserId: ownerUserId,
            kinds: const {MemoryKind.episodic},
            scope: scope,
            queryText: intent.freeText,
            entityFilter: entities,
            topK: perSlotLimit,
          )
        : const <MemoryHit>[];

    // Recent events — time-window slice. Always pulled.
    final eventsAll = await runtime.recentEvents(
      ownerUserId: ownerUserId,
      window: eventWindow,
      limit: perSlotLimit * 2,
    );
    // Subset filtered by entities (separately from the top feed) so
    // the LLM has the focused view without re-filtering.
    final eventsRelated = (entities == null || entities.isEmpty)
        ? <EventRecord>[]
        : eventsAll
              .where((e) => e.entities.intersection(entities).isNotEmpty)
              .take(perSlotLimit)
              .toList(growable: false);
    final eventsRecent = eventsAll.length <= perSlotLimit
        ? eventsAll
        : eventsAll.sublist(0, perSlotLimit);

    return ContextPackMemory(
      userPreferences: preferences.map((h) => h.record).toList(growable: false),
      recentEvents: eventsRecent,
      relatedDecisions: episodicHits
          .map((h) => h.record)
          .toList(growable: false),
      applicableRules: rules.map((h) => h.record).toList(growable: false),
      relatedEvents: eventsRelated,
    );
  }
}
