import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/db/providers.dart';
import '../../../data/market/market_data_providers.dart';
import '../../../data/repositories/mutation_context.dart';
import '../../../data/repositories/providers.dart';
import '../application/scan_orchestrator.dart';
import '../domain/approved_underlying.dart';
import '../domain/options_opportunity.dart';
import '../domain/options_strategy_profile.dart';
import '../domain/services/opportunity_scorer.dart';
import '../domain/trade_journal_entry.dart';
import 'approved_underlyings_repository.dart';
import 'options_opportunity_cache_repository.dart';
import 'options_strategy_profile_repository.dart';
import 'trade_journal_repository.dart';

final optionsStrategyProfileRepositoryProvider =
    FutureProvider<OptionsStrategyProfileRepository>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  final outbox = await ref.watch(outboxStoreProvider.future);
  final stamper = await ref.watch(mutationStamperProvider.future);
  return OptionsStrategyProfileRepository(
    db: db,
    outbox: outbox,
    stamper: stamper,
  );
});

final approvedUnderlyingsRepositoryProvider =
    FutureProvider<ApprovedUnderlyingsRepository>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  final outbox = await ref.watch(outboxStoreProvider.future);
  final stamper = await ref.watch(mutationStamperProvider.future);
  return ApprovedUnderlyingsRepository(
    db: db,
    outbox: outbox,
    stamper: stamper,
  );
});

/// Streams the current user's [OptionsStrategyProfile], `null` when the
/// user hasn't configured one yet (first run).
final optionsStrategyProfileProvider =
    StreamProvider.autoDispose<OptionsStrategyProfile?>((ref) async* {
  final repo = await ref.watch(optionsStrategyProfileRepositoryProvider.future);
  final ownerUserId = await ref.watch(currentUserIdProvider)();
  yield* repo.watch(ownerUserId);
});

/// Streams the user's approved underlyings list (alphabetic by symbol).
final approvedUnderlyingsProvider =
    StreamProvider.autoDispose<List<ApprovedUnderlying>>((ref) async* {
  final repo = await ref.watch(approvedUnderlyingsRepositoryProvider.future);
  final ownerUserId = await ref.watch(currentUserIdProvider)();
  yield* repo.watchActive(ownerUserId);
});

/// Override hook for tests — production wiring uses [ScoringWeights]'
/// defaults from `docs/options-income.md` §7.2.
final optionsScoringWeightsProvider = Provider<ScoringWeights>((ref) {
  return const ScoringWeights();
});

final opportunityScorerProvider = Provider<OpportunityScorer>((ref) {
  return OpportunityScorer(weights: ref.watch(optionsScoringWeightsProvider));
});

final optionsOpportunityCacheRepositoryProvider =
    FutureProvider<OptionsOpportunityCacheRepository>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  final repo = OptionsOpportunityCacheRepository(db: db);
  ref.onDispose(repo.dispose);
  return repo;
});

final scanOrchestratorProvider = FutureProvider<ScanOrchestrator>((ref) async {
  final chain = ref.watch(yfinanceOptionsProviderProvider);
  final scorer = ref.watch(opportunityScorerProvider);
  final cache =
      await ref.watch(optionsOpportunityCacheRepositoryProvider.future);
  return ScanOrchestrator(
    chainProvider: chain,
    scorer: scorer,
    cache: cache,
  );
});

/// Latest scan batch surfaced from the local cache. Refreshes itself
/// whenever the cache repository emits a write — see
/// `OptionsOpportunityCacheRepository.changes`.
final cachedOpportunitiesProvider =
    FutureProvider.autoDispose<List<OptionsOpportunity>>((ref) async {
  final repo =
      await ref.watch(optionsOpportunityCacheRepositoryProvider.future);
  final ownerUserId = await ref.watch(currentUserIdProvider)();
  final sub = repo.changes.listen((uid) {
    if (uid == ownerUserId) ref.invalidateSelf();
  });
  ref.onDispose(sub.cancel);
  return repo.getLatest(ownerUserId);
});

final tradeJournalRepositoryProvider =
    FutureProvider<TradeJournalRepository>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  final outbox = await ref.watch(outboxStoreProvider.future);
  final stamper = await ref.watch(mutationStamperProvider.future);
  return TradeJournalRepository(db: db, outbox: outbox, stamper: stamper);
});

final tradeJournalEntriesProvider =
    StreamProvider.autoDispose<List<TradeJournalEntry>>((ref) async* {
  final repo = await ref.watch(tradeJournalRepositoryProvider.future);
  final ownerUserId = await ref.watch(currentUserIdProvider)();
  yield* repo.watchActive(ownerUserId);
});

/// Metadata about the most recent scan (id + scanned_at + is_stale).
final latestScanStateProvider =
    FutureProvider.autoDispose<ScanCacheState?>((ref) async {
  final repo =
      await ref.watch(optionsOpportunityCacheRepositoryProvider.future);
  final ownerUserId = await ref.watch(currentUserIdProvider)();
  final sub = repo.changes.listen((uid) {
    if (uid == ownerUserId) ref.invalidateSelf();
  });
  ref.onDispose(sub.cancel);
  return repo.latestScanState(ownerUserId);
});
