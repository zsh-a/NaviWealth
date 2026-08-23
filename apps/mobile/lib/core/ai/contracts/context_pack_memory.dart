/// Context pack assembled by [ContextBuilder] for an LLM turn
/// (`docs/architecture/lifeos-shell.md` §6, D-1.7b).
///
/// Named `context_pack_memory.dart` to avoid colliding with the older
/// [ContextPack] in `task_context.dart` (legacy chat-prompt envelope —
/// kept untouched). This module is the **Memory Runtime's** output
/// shape, structured by explicit retrieval roles plus the recent event stream.
///
/// Distinct from raw retrieval hits: the builder pre-filters by intent
/// (entity / scope / time-window / kind) and pre-classifies hits into
/// the LLM-friendly buckets. The LLM doesn't have to re-categorise.
library;

import 'event_record.dart';
import 'memory_record.dart';

/// What the agent is trying to do — handed to [ContextBuilder] so it
/// can score memories. Optional everywhere: an empty intent returns a
/// generic profile pack.
class ContextIntent {
  const ContextIntent({
    this.freeText,
    this.entities = const <String>{},
    this.scope,
    this.kindHints = const <MemoryKind>{},
  });

  /// Natural-language phrasing of the intent (e.g. "should I close
  /// my NVDA put"). Embedded as the query vector.
  final String? freeText;

  /// Hard entity matches the builder must satisfy (overlap > 0 boosts
  /// score; empty = no boost).
  final Set<String> entities;

  /// Restrict to memories in this scope (e.g. `'options_trading'`).
  /// `null` = global.
  final String? scope;

  /// If non-empty, only consider memories of these kinds. Empty =
  /// all kinds.
  final Set<MemoryKind> kindHints;
}

/// Pre-assembled, kind-classified pack the LLM sees.
class ContextPackMemory {
  const ContextPackMemory({
    required this.userPreferences,
    required this.recentEvents,
    required this.relatedDecisions,
    required this.relatedEpisodes,
    required this.derivedPatterns,
    required this.derivedGuidance,
    required this.applicableRules,
    required this.relatedEvents,
  });

  /// `semantic` memories — long-term facts about the user. Filtered
  /// by scope + validity window.
  final List<MemoryRecord> userPreferences;

  /// Last-N events (any source family and event kind) in the recency window. The
  /// builder doesn't try to be smart here — recent_events is the raw
  /// timeline feed, used for "what was the user doing lately".
  final List<EventRecord> recentEvents;

  /// Source-of-truth Decision projections ranked against the intent.
  final List<MemoryRecord> relatedDecisions;

  /// Important experiences and legacy episodic records ranked by intent.
  final List<MemoryRecord> relatedEpisodes;

  /// Deterministic or model-derived patterns; never instruction authority.
  final List<MemoryRecord> derivedPatterns;

  /// Retrieved guidance that remains evidence rather than an instruction.
  final List<MemoryRecord> derivedGuidance;

  /// `procedural` memories matching scope. Rules the LLM should
  /// follow when proposing actions.
  final List<MemoryRecord> applicableRules;

  /// Subset of [recentEvents] that match intent entities — duplicated
  /// here so prompts can use either the full feed or the focused slice
  /// without re-filtering.
  final List<EventRecord> relatedEvents;

  bool get isEmpty =>
      userPreferences.isEmpty &&
      recentEvents.isEmpty &&
      relatedDecisions.isEmpty &&
      relatedEpisodes.isEmpty &&
      derivedPatterns.isEmpty &&
      derivedGuidance.isEmpty &&
      applicableRules.isEmpty;

  Map<String, Object?> toJson() => <String, Object?>{
    'user_preferences': userPreferences
        .map((m) => m.toJson())
        .toList(growable: false),
    'recent_events': recentEvents
        .map((e) => e.toJson())
        .toList(growable: false),
    'related_decisions': relatedDecisions
        .map((m) => m.toJson())
        .toList(growable: false),
    'related_episodes': relatedEpisodes
        .map((m) => m.toJson())
        .toList(growable: false),
    'derived_patterns': derivedPatterns
        .map((m) => m.toJson())
        .toList(growable: false),
    'derived_guidance': derivedGuidance
        .map((m) => m.toJson())
        .toList(growable: false),
    'applicable_rules': applicableRules
        .map((m) => m.toJson())
        .toList(growable: false),
    'related_events': relatedEvents
        .map((e) => e.toJson())
        .toList(growable: false),
  };
}
