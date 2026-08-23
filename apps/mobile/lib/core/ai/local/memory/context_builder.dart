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
/// | related_decisions  | `role=decision` recall            | hybrid-scored by intent.freeText + entities              |
/// | related_episodes   | `role=episode|legacy` recall       | hybrid-scored by intent.freeText + entities              |
/// | derived_patterns   | `role=pattern` recall              | hybrid-scored by intent.freeText + entities              |
/// | derived_guidance   | `role=guidance` recall             | hybrid-scored by intent.freeText + entities              |
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
    Set<String>? sourcePrefixes,
    int perSlotLimit = 6,
    Duration eventWindow = const Duration(days: 30),
  }) async {
    if (sourcePrefixes != null && sourcePrefixes.isEmpty) {
      return const ContextPackMemory(
        userPreferences: <MemoryRecord>[],
        recentEvents: <EventRecord>[],
        relatedDecisions: <MemoryRecord>[],
        relatedEpisodes: <MemoryRecord>[],
        derivedPatterns: <MemoryRecord>[],
        derivedGuidance: <MemoryRecord>[],
        applicableRules: <MemoryRecord>[],
        relatedEvents: <EventRecord>[],
      );
    }
    final scope = intent.scope;
    final entities = intent.entities.isEmpty ? null : intent.entities;
    final queryText = intent.freeText?.trim();
    final queryVector = queryText == null || queryText.isEmpty
        ? null
        : await runtime.embedder.embed(queryText);

    // Semantic preferences — no semantic query needed; the user's
    // long-term facts should always come through when in-scope.
    final preferenceHits =
        intent.kindHints.isEmpty ||
            intent.kindHints.contains(MemoryKind.semantic)
        ? await runtime.recall(
            ownerUserId: ownerUserId,
            kinds: const {MemoryKind.semantic},
            roles: const {MemoryRole.legacy},
            scope: scope,
            sourcePrefixes: sourcePrefixes,
            entityFilter: entities,
            topK: perSlotLimit,
          )
        : const <MemoryHit>[];
    final preferences = preferenceHits;

    // Procedural rules — explicit; embed scope-match only.
    final ruleHits =
        intent.kindHints.isEmpty ||
            intent.kindHints.contains(MemoryKind.procedural)
        ? await runtime.recall(
            ownerUserId: ownerUserId,
            kinds: const {MemoryKind.procedural},
            roles: const {MemoryRole.legacy},
            scope: scope,
            sourcePrefixes: sourcePrefixes,
            entityFilter: entities,
            topK: perSlotLimit,
          )
        : const <MemoryHit>[];
    final rules = ruleHits;

    // Decision and episode roles are queried independently so a high-volume
    // episode stream cannot crowd source-of-truth decisions out of top-k.
    final decisionHits =
        intent.kindHints.isEmpty ||
            intent.kindHints.contains(MemoryKind.episodic)
        ? await runtime.recall(
            ownerUserId: ownerUserId,
            kinds: const {MemoryKind.episodic},
            roles: const {MemoryRole.decision},
            scope: scope,
            queryVector: queryVector,
            entityFilter: entities,
            sourcePrefixes: sourcePrefixes,
            topK: perSlotLimit,
          )
        : const <MemoryHit>[];
    final episodeHits =
        intent.kindHints.isEmpty ||
            intent.kindHints.contains(MemoryKind.episodic)
        ? await runtime.recall(
            ownerUserId: ownerUserId,
            kinds: const {MemoryKind.episodic},
            roles: const {MemoryRole.episode, MemoryRole.legacy},
            scope: scope,
            queryVector: queryVector,
            entityFilter: entities,
            sourcePrefixes: sourcePrefixes,
            topK: perSlotLimit,
          )
        : const <MemoryHit>[];

    final patternHits = await runtime.recall(
      ownerUserId: ownerUserId,
      kinds: intent.kindHints.isEmpty
          ? const <MemoryKind>{
              MemoryKind.semantic,
              MemoryKind.episodic,
              MemoryKind.procedural,
            }
          : intent.kindHints,
      roles: const {MemoryRole.pattern},
      scope: scope,
      queryVector: queryVector,
      entityFilter: entities,
      sourcePrefixes: sourcePrefixes,
      topK: perSlotLimit,
    );
    final guidanceHits = await runtime.recall(
      ownerUserId: ownerUserId,
      kinds: intent.kindHints.isEmpty
          ? const <MemoryKind>{
              MemoryKind.semantic,
              MemoryKind.episodic,
              MemoryKind.procedural,
            }
          : intent.kindHints,
      roles: const {MemoryRole.guidance},
      scope: scope,
      queryVector: queryVector,
      entityFilter: entities,
      sourcePrefixes: sourcePrefixes,
      topK: perSlotLimit,
    );

    // Recent events — time-window slice. Always pulled.
    final eventsAll = await runtime.recentEvents(
      ownerUserId: ownerUserId,
      sourcePrefixes: sourcePrefixes,
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
      relatedDecisions: decisionHits
          .map((hit) => hit.record)
          .toList(growable: false),
      relatedEpisodes: episodeHits
          .map((hit) => hit.record)
          .toList(growable: false),
      derivedPatterns: patternHits
          .map((hit) => hit.record)
          .toList(growable: false),
      derivedGuidance: guidanceHits
          .map((hit) => hit.record)
          .toList(growable: false),
      applicableRules: rules.map((h) => h.record).toList(growable: false),
      relatedEvents: eventsRelated,
    );
  }
}
