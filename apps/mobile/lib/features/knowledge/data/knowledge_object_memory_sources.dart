part of 'knowledge_object_memory_indexers.dart';

// KnowledgeOS Memory sources (single catalogue).
//
// `MemoryRuntime.recall(source:)` is an exact match; there is no `know:*`
// wildcard. Every type's source string is declared here, and the dedupe /
// cross-type search tools iterate [kKnowledgeMemorySources]. Decision has
// its own indexer but imports its source from here so this stays the one
// place a new type is registered.
const String kKnowledgeNoteMemorySource = 'know:notes';
const String kKnowledgePrincipleMemorySource = 'know:principles';
const String kKnowledgeAssumptionMemorySource = 'know:assumptions';
const String kKnowledgeConceptMemorySource = 'know:concepts';
const String kKnowledgeExperimentMemorySource = 'know:experiments';
const String kKnowledgeDecisionMemorySource = 'know:decisions';
const String kKnowledgeRoutineMemorySource = 'know:routines';

/// Every KnowledgeOS Memory source keyed by a short type token
/// (`docs/domains/knowledgeos-domain.md` §15.3). Iterated by the dedupe /
/// cross-type search tools. Add a new type's source above and here.
const Map<String, String> kKnowledgeMemorySources = <String, String>{
  'note': kKnowledgeNoteMemorySource,
  'principle': kKnowledgePrincipleMemorySource,
  'assumption': kKnowledgeAssumptionMemorySource,
  'concept': kKnowledgeConceptMemorySource,
  'experiment': kKnowledgeExperimentMemorySource,
  'decision': kKnowledgeDecisionMemorySource,
  'routine': kKnowledgeRoutineMemorySource,
};

/// Knowledge types where a near-duplicate can be turned into a supported
/// `knowledge_merge` proposal. Routine rows are searchable, but excluded
/// from dedupe until they get a merge pointer and apply path.
const Map<String, String> kKnowledgeDedupeMemorySources = <String, String>{
  'note': kKnowledgeNoteMemorySource,
  'principle': kKnowledgePrincipleMemorySource,
  'assumption': kKnowledgeAssumptionMemorySource,
  'concept': kKnowledgeConceptMemorySource,
  'experiment': kKnowledgeExperimentMemorySource,
  'decision': kKnowledgeDecisionMemorySource,
};
