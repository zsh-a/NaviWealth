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
import '../domain/wheel_lifecycle.dart';
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

/// Per-underlying Wheel lifecycles derived from the live trade journal
/// (`roadmap-next.md` §3.3 P4). Pure derivation — no extra reads — so
/// this provider rebuilds whenever the journal stream emits.
///
/// Sorted by current stage's salience: open positions first, then resting
/// states (sharesHeld / cashWaiting), then closed-out symbols. Within
/// each bucket, ordered alphabetically so the UI stays stable across
/// re-emits.
final wheelLifecyclesProvider =
    Provider.autoDispose<AsyncValue<List<WheelLifecycle>>>((ref) {
  final entriesAsync = ref.watch(tradeJournalEntriesProvider);
  return entriesAsync.whenData((entries) {
    final symbols = entries.map((e) => e.symbol).toSet();
    final cycles = <WheelLifecycle>[];
    for (final symbol in symbols) {
      final symbolEntries = entries.where((e) => e.symbol == symbol);
      // Pick any entry's currency as the cycle's currency — every
      // journal entry on the same underlying must share one (different
      // currencies on the same symbol would be a data-integrity bug).
      final currency = symbolEntries.first.currency;
      cycles.add(
        buildWheelLifecycle(
          symbol: symbol,
          currency: currency,
          entries: symbolEntries,
        ),
      );
    }
    cycles.sort((a, b) {
      final aRank = _stageRank(a.stage);
      final bRank = _stageRank(b.stage);
      if (aRank != bRank) return aRank.compareTo(bRank);
      return a.symbol.compareTo(b.symbol);
    });
    return cycles;
  });
});

int _stageRank(WheelStage stage) => switch (stage) {
      // Active (open) positions first — these are where the user is on
      // the hook.
      WheelStage.shortPut => 0,
      WheelStage.shortCall => 0,
      // Resting between positions, but still holding either cash earmark
      // or shares.
      WheelStage.putAssigned => 1,
      WheelStage.sharesHeld => 1,
      WheelStage.cashWaiting => 2,
      // Terminal-ish — past events the user might want to review.
      WheelStage.callExpired => 3,
      WheelStage.putExpired => 3,
      WheelStage.callCalled => 4,
      WheelStage.between => 5,
    };

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
