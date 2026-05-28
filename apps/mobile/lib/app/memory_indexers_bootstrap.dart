/// Composition root for Memory Runtime indexers
/// (`docs/lifeos-shell.md` §6, D-1.7b).
///
/// `core/ai/local/memory/providers.dart` stays domain-neutral
/// (northstar §2.1: `core/` must not import `features/`). This file
/// lives in `app/` so it is allowed to reach into each feature's
/// indexer provider and wire it up at bootstrap.
///
/// Add a new domain caller (e.g. HealthOS sleep summaries, D-2.4) by
/// adding one `ref.watch(...)` line below. No changes elsewhere.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/health/data/health_metric_memory_indexer.dart';
import '../features/knowledge/data/knowledge_decision_memory_indexer.dart';
import '../features/options_income/data/trade_journal_memory_indexer.dart';

/// Eager bootstrap for every Memory Layer indexer. `bootstrap.dart`
/// reads this once at startup; reading it triggers the indexer
/// providers and subscribes them to their source streams.
///
/// Domain-level opt-in (`domainOptInsProvider`) is enforced **inside**
/// each indexer provider, so the bootstrap unconditionally watches
/// every domain. HealthOS D-2.4b: the indexer's own provider returns
/// early without subscribing when Health is OFF, so reading it here
/// for an install with Health OFF is cheap.
final memoryLayerBootstrapProvider = Provider<void>((ref) {
  ref.watch(tradeJournalMemoryIndexerProvider);
  ref.watch(healthMetricMemoryIndexerProvider);
  ref.watch(knowledgeDecisionMemoryIndexerProvider);
});
