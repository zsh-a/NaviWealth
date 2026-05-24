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

import '../features/options_income/data/trade_journal_memory_indexer.dart';

/// Eager bootstrap for every Memory Layer indexer. `bootstrap.dart`
/// reads this once at startup; reading it triggers the indexer
/// providers and subscribes them to their source streams.
final memoryLayerBootstrapProvider = Provider<void>((ref) {
  ref.watch(tradeJournalMemoryIndexerProvider);
  // Add new indexers here as new domains come online:
  //   ref.watch(sleepDailyMemoryIndexerProvider);  // HealthOS D-2.4
});
