import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naviwealth/core/persistence/providers.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/core/sync/outbox_provider.dart';
import 'package:naviwealth/features/finance/data/market/market_data_providers.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_providers.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/finance/income_strategy/data/income_strategy_plan_providers.dart';
import 'package:naviwealth/features/finance/income_strategy/domain/income_strategy.dart';
import 'package:naviwealth/features/finance/income_strategy/domain/income_strategy_plan.dart';
import 'package:naviwealth/features/finance/investment/data/providers.dart';
import 'package:naviwealth/features/finance/market/domain/asset_market.dart';

import '../application/options_journal_ledger_service.dart';
import '../application/scan_orchestrator.dart';
import '../domain/approved_underlying.dart';
import '../domain/leaps_call_position.dart';
import '../domain/options_opportunity.dart';
import '../domain/options_strategy_profile.dart';
import '../domain/options_trade_stats.dart';
import '../domain/services/opportunity_scorer.dart';
import '../domain/trade_journal_entry.dart';
import '../domain/wheel_lifecycle.dart';
import 'leaps_call_position_repository.dart';
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

/// Streams the current user's [OptionsStrategyProfile], `null` when the
/// user hasn't configured one yet (first run).
final optionsStrategyProfileProvider =
    StreamProvider.autoDispose<OptionsStrategyProfile?>((ref) async* {
      final repo = await ref.watch(
        optionsStrategyProfileRepositoryProvider.future,
      );
      final ownerUserId = await ref.watch(currentUserIdProvider)();
      yield* repo.watch(ownerUserId);
    });

/// Projects Wheel-enabled plans into the approved-underlying view.
///
/// This remains a derived value of the plan stream rather than a second
/// persisted source of truth, so every plan emission updates consumers.
final approvedUnderlyingsProvider =
    Provider.autoDispose<AsyncValue<List<ApprovedUnderlying>>>((ref) {
      return ref.watch(incomeStrategyPlansProvider).whenData((plans) {
        return [
          for (final plan in plans)
            if (plan.enabledSleeves.contains(IncomeStrategySleeveKind.wheel))
              _approvedUnderlyingFromPlan(plan),
        ]..sort((a, b) => a.symbol.compareTo(b.symbol));
      });
    });

ApprovedUnderlying _approvedUnderlyingFromPlan(IncomeStrategyPlan plan) {
  final intent = plan.intent(IncomeStrategySleeveKind.wheel);
  return ApprovedUnderlying(
    id: plan.assetId,
    symbol: plan.symbol,
    market: assetMarketFromWire(plan.market) ?? AssetMarket.unknown,
    allowPut:
        intent?.boolValue(
          WheelIncomeStrategySettings.allowPut,
          fallback: true,
        ) ??
        true,
    allowCall:
        intent?.boolValue(
          WheelIncomeStrategySettings.allowCall,
          fallback: true,
        ) ??
        true,
    maxBuyPrice: intent?.decimalValue(WheelIncomeStrategySettings.maxBuyPrice),
    minSellPrice: intent?.decimalValue(
      WheelIncomeStrategySettings.minSellPrice,
    ),
    maxPositionWeight: plan.maxPositionWeight,
    notes: plan.notes,
    sync: plan.sync,
  );
}

/// Override hook for tests — production wiring uses [ScoringWeights]'
/// defaults from `docs/domains/options-income.md` §7.2.
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
  final cache = await ref.watch(
    optionsOpportunityCacheRepositoryProvider.future,
  );
  return ScanOrchestrator(chainProvider: chain, scorer: scorer, cache: cache);
});

/// Latest scan batch surfaced from the local cache. Refreshes itself
/// whenever the cache repository emits a write — see
/// `OptionsOpportunityCacheRepository.changes`.
final cachedOpportunitiesProvider =
    FutureProvider.autoDispose<List<OptionsOpportunity>>((ref) async {
      final repoFuture = ref.watch(
        optionsOpportunityCacheRepositoryProvider.future,
      );
      final currentUserId = ref.watch(currentUserIdProvider);
      final repo = await repoFuture;
      if (!ref.mounted) return const <OptionsOpportunity>[];
      final ownerUserId = await currentUserId();
      if (!ref.mounted) return const <OptionsOpportunity>[];
      final sub = repo.changes.listen((uid) {
        if (uid == ownerUserId && ref.mounted) ref.invalidateSelf();
      });
      ref.onDispose(sub.cancel);
      return repo.getLatest(ownerUserId);
    });

final tradeJournalRepositoryProvider = FutureProvider<TradeJournalRepository>((
  ref,
) async {
  final db = await ref.watch(appDatabaseProvider.future);
  final outbox = await ref.watch(outboxStoreProvider.future);
  final stamper = await ref.watch(mutationStamperProvider.future);
  return TradeJournalRepository(db: db, outbox: outbox, stamper: stamper);
});

final leapsCallPositionRepositoryProvider =
    FutureProvider<LeapsCallPositionRepository>((ref) async {
      final db = await ref.watch(appDatabaseProvider.future);
      final outbox = await ref.watch(outboxStoreProvider.future);
      final stamper = await ref.watch(mutationStamperProvider.future);
      return LeapsCallPositionRepository(
        db: db,
        outbox: outbox,
        stamper: stamper,
      );
    });

final leapsCallPositionsProvider =
    StreamProvider.autoDispose<List<LeapsCallPosition>>((ref) async* {
      final repo = await ref.watch(leapsCallPositionRepositoryProvider.future);
      final ownerUserId = await ref.watch(currentUserIdProvider)();
      yield* repo.watchActive(ownerUserId);
    });

final optionsJournalLedgerServiceProvider =
    FutureProvider<OptionsJournalLedgerService>((ref) async {
      final journalEntryRepo = await ref.watch(
        journalEntryRepositoryProvider.future,
      );
      final manualAssetRepo = await ref.watch(
        manualAssetRepositoryProvider.future,
      );
      final securitiesAssetRepo = await ref.watch(
        securitiesAssetRepositoryProvider.future,
      );
      final priceRepo = await ref.watch(priceRepositoryProvider.future);
      final stamper = await ref.watch(mutationStamperProvider.future);
      return OptionsJournalLedgerService(
        journalEntryRepo: journalEntryRepo,
        manualAssetRepo: manualAssetRepo,
        securitiesAssetRepo: securitiesAssetRepo,
        priceRepo: priceRepo,
        holdingService: () => ref.read(holdingServiceProvider.future),
        currentUserId: stamper.currentUserId,
      );
    });

final tradeJournalEntriesProvider =
    StreamProvider.autoDispose<List<TradeJournalEntry>>((ref) async* {
      final repo = await ref.watch(tradeJournalRepositoryProvider.future);
      final ownerUserId = await ref.watch(currentUserIdProvider)();
      yield* repo.watchActive(ownerUserId);
    });

final optionsTradeStatsProvider =
    Provider.autoDispose<AsyncValue<OptionsTradeStats>>((ref) {
      final entriesAsync = ref.watch(tradeJournalEntriesProvider);
      return entriesAsync.whenData(buildOptionsTradeStats);
    });

/// Per-underlying Wheel lifecycles derived from the live trade journal
/// (`docs/domains/options-income.md` §12 P4). Pure derivation — no extra reads — so
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
  WheelStage.mixedOpen => 0,
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
final latestScanStateProvider = FutureProvider.autoDispose<ScanCacheState?>((
  ref,
) async {
  final repoFuture = ref.watch(
    optionsOpportunityCacheRepositoryProvider.future,
  );
  final currentUserId = ref.watch(currentUserIdProvider);
  final repo = await repoFuture;
  if (!ref.mounted) return null;
  final ownerUserId = await currentUserId();
  if (!ref.mounted) return null;
  final sub = repo.changes.listen((uid) {
    if (uid == ownerUserId && ref.mounted) ref.invalidateSelf();
  });
  ref.onDispose(sub.cancel);
  return repo.latestScanState(ownerUserId);
});
