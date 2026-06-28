/// Composition root for Memory Runtime indexers
/// (`docs/architecture/lifeos-shell.md` §6, D-1.7b).
///
/// `core/ai/local/memory/providers.dart` stays domain-neutral
/// (northstar §2.1: `core/` must not import `features/`). This file
/// lives in `app/` so it is allowed to reach into each feature's
/// indexer provider and wire it up at bootstrap.
///
/// Add a new domain indexer by adding one `ref.watch(...)` line below.
/// No changes elsewhere.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/execution/data/execution_memory_indexer.dart';
import '../features/health/data/health_metric_memory_indexer.dart';
import '../features/knowledge/data/knowledge_decision_memory_indexer.dart';
import '../features/knowledge/data/knowledge_object_memory_indexers.dart';
import '../features/options_income/data/trade_journal_memory_indexer.dart';

/// Eager bootstrap for every Memory Layer indexer. `bootstrap.dart`
/// reads this once at startup; reading it triggers the indexer
/// providers and subscribes them to their source streams.
///
/// Domain-level opt-in (`domainOptInsProvider`) is enforced **inside**
/// each indexer provider, so the bootstrap unconditionally watches
/// every domain. A disabled domain's indexer returns early without
/// subscribing, so reading it here is cheap.
final memoryLayerBootstrapProvider = Provider<void>((ref) {
  ref.watch(tradeJournalMemoryIndexerProvider);
  ref.watch(executionMemoryIndexerProvider);
  ref.watch(healthMetricMemoryIndexerProvider);
  ref.watch(knowledgeDecisionMemoryIndexerProvider);
  // KnowledgeOS non-Decision indexers (§3 "写一份,索引两次").
  ref.watch(knowledgeNoteMemoryIndexerProvider);
  ref.watch(knowledgePrincipleMemoryIndexerProvider);
  ref.watch(knowledgeAssumptionMemoryIndexerProvider);
  ref.watch(knowledgeConceptMemoryIndexerProvider);
  ref.watch(knowledgeExperimentMemoryIndexerProvider);
  ref.watch(knowledgeRoutineMemoryIndexerProvider);
});
