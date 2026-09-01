import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naviwealth/core/persistence/providers.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/core/sync/outbox_provider.dart';
import 'package:naviwealth/features/finance/investment/data/event_timeline_providers.dart';
import 'package:naviwealth/features/finance/investment/data/watchlist_providers.dart';
import 'package:naviwealth/features/finance/market/domain/corporate_action_provider.dart';
import 'package:naviwealth/features/finance/market/domain/market_corporate_action.dart';

import 'watchlist_simulation_repository.dart';

final watchlistSimulationRepositoryProvider =
    FutureProvider<WatchlistSimulationRepository>((ref) async {
      final db = await ref.watch(appDatabaseProvider.future);
      final outbox = await ref.watch(outboxStoreProvider.future);
      final stamper = await ref.watch(mutationStamperProvider.future);
      return WatchlistSimulationRepository(
        db: db,
        outbox: outbox,
        stamper: stamper,
      );
    });

final watchlistSimulationsProvider =
    StreamProvider.autoDispose<List<WatchlistSimulation>>((ref) async* {
      final repository = await ref.watch(
        watchlistSimulationRepositoryProvider.future,
      );
      final ownerUserId = await ref.watch(currentUserIdProvider)();
      yield* repository.watchActive(ownerUserId);
    });

final watchlistSimulationAllocationProvider = StreamProvider.autoDispose
    .family<ResolvedWatchlistSimulationAllocation, String>((
      ref,
      simulationId,
    ) async* {
      final repository = await ref.watch(
        watchlistSimulationRepositoryProvider.future,
      );
      final ownerUserId = await ref.watch(currentUserIdProvider)();
      yield* repository.watchResolvedAllocation(
        ownerUserId: ownerUserId,
        simulationId: simulationId,
      );
    });

final watchlistSimulationPositionsProvider = StreamProvider.autoDispose
    .family<List<WatchlistSimulationPosition>, String>((
      ref,
      simulationId,
    ) async* {
      final repository = await ref.watch(
        watchlistSimulationRepositoryProvider.future,
      );
      final ownerUserId = await ref.watch(currentUserIdProvider)();
      yield* repository.watchPositions(
        ownerUserId: ownerUserId,
        simulationId: simulationId,
      );
    });

final watchlistSimulationActionEntriesProvider = StreamProvider.autoDispose
    .family<List<WatchlistSimulationActionEntry>, String>((
      ref,
      simulationId,
    ) async* {
      final allocation = ref
          .watch(watchlistSimulationAllocationProvider(simulationId))
          .asData
          ?.value;
      if (allocation == null || !allocation.isUsable) {
        yield const <WatchlistSimulationActionEntry>[];
        return;
      }
      final repository = await ref.watch(
        watchlistSimulationRepositoryProvider.future,
      );
      final ownerUserId = await ref.watch(currentUserIdProvider)();
      yield* repository
          .watchActionEntries(
            ownerUserId: ownerUserId,
            simulationId: simulationId,
          )
          .map(
            (entries) => entries
                .where(
                  (entry) =>
                      (entry.allocationBasisKey == null &&
                          !entry.hasPaperValue) ||
                      allocation.validAllocationBasisKeys.contains(
                        entry.allocationBasisKey,
                      ),
                )
                .toList(growable: false),
          );
    });

class WatchlistSimulationActionReconciliation {
  const WatchlistSimulationActionReconciliation({
    required this.materializedCount,
    required this.failedSymbolCount,
    required this.unsupportedSymbolCount,
    this.partialSymbolCount = 0,
    this.staleSymbolCount = 0,
    this.allocationUnavailable = false,
  });

  final int materializedCount;
  final int failedSymbolCount;
  final int unsupportedSymbolCount;
  final int partialSymbolCount;
  final int staleSymbolCount;
  final bool allocationUnavailable;

  bool get hasCoverageIssues =>
      allocationUnavailable ||
      failedSymbolCount > 0 ||
      unsupportedSymbolCount > 0 ||
      partialSymbolCount > 0 ||
      staleSymbolCount > 0;
}

/// Reconciles normalized provider candidates into deterministic paper-only
/// references. Reading this provider never writes real portfolio/ledger rows.
final watchlistSimulationActionReconciliationProvider = FutureProvider
    .autoDispose
    .family<WatchlistSimulationActionReconciliation, String>((
      ref,
      simulationId,
    ) async {
      final simulations = await ref.watch(watchlistSimulationsProvider.future);
      WatchlistSimulation? simulation;
      for (final candidate in simulations) {
        if (candidate.id == simulationId) {
          simulation = candidate;
          break;
        }
      }
      if (simulation == null) {
        return const WatchlistSimulationActionReconciliation(
          materializedCount: 0,
          failedSymbolCount: 0,
          unsupportedSymbolCount: 0,
        );
      }
      final repository = await ref.watch(
        watchlistSimulationRepositoryProvider.future,
      );
      final lifecycleAsOf = DateTime.now().toUtc();
      final allocation = await ref.watch(
        watchlistSimulationAllocationProvider(simulationId).future,
      );
      if (!allocation.isUsable) {
        return const WatchlistSimulationActionReconciliation(
          materializedCount: 0,
          failedSymbolCount: 0,
          unsupportedSymbolCount: 0,
          allocationUnavailable: true,
        );
      }
      final locallyAdvanced = await repository.advanceDividendLifecycle(
        simulation: simulation,
        asOf: lifecycleAsOf,
      );
      final positions = allocation.positions;
      final items = await ref.watch(watchlistItemsProvider.future);
      final itemById = {for (final item in items) item.id: item};
      final targetsById = <String, WatchlistSimulationActionTarget>{
        for (final position in positions)
          if (itemById[position.watchlistItemId] case final item?)
            position.watchlistItemId: WatchlistSimulationActionTarget(
              watchlistItemId: position.watchlistItemId,
              symbol: item.symbol,
              market: item.market,
            ),
      };
      final persistedTargets = await repository.listActionTargets(
        ownerUserId: simulation.sync.ownerUserId,
        simulationId: simulation.id,
      );
      for (final target in persistedTargets) {
        targetsById.putIfAbsent(target.watchlistItemId, () => target);
      }
      final corporateActions = await ref.watch(
        corporateActionsServiceProvider.future,
      );
      final actionsByItemId = <String, Iterable<MarketCorporateAction>>{};
      final trustedAdjustmentCoverageItemIds = <String>{};
      final rangeEnd = lifecycleAsOf.add(const Duration(days: 365));
      var failedSymbolCount = 0;
      var unsupportedSymbolCount = 0;
      var partialSymbolCount = 0;
      var staleSymbolCount = 0;
      for (final target in targetsById.values) {
        final result = await corporateActions.fetchRange(
          CorporateActionFetchRequest(
            symbol: target.symbol,
            market: target.market,
            from: simulation.baselineAt.subtract(const Duration(days: 1)),
            to: rangeEnd,
          ),
        );
        switch (result.disposition) {
          case CorporateActionFetchDisposition.success:
            actionsByItemId[target.watchlistItemId] = result.actions;
            trustedAdjustmentCoverageItemIds.add(target.watchlistItemId);
          case CorporateActionFetchDisposition.authoritativeEmpty:
            trustedAdjustmentCoverageItemIds.add(target.watchlistItemId);
          case CorporateActionFetchDisposition.partial:
            actionsByItemId[target.watchlistItemId] = result.actions;
            partialSymbolCount++;
          case CorporateActionFetchDisposition.stale:
            staleSymbolCount++;
          case CorporateActionFetchDisposition.unsupported:
            unsupportedSymbolCount++;
          case CorporateActionFetchDisposition.failure:
            failedSymbolCount++;
        }
      }
      final materialized = await repository.materializeDividendReferences(
        simulation: simulation,
        actionsByWatchlistItemId: actionsByItemId,
        trustedAdjustmentCoverageItemIds: trustedAdjustmentCoverageItemIds,
        lifecycleAsOf: lifecycleAsOf,
      );
      return WatchlistSimulationActionReconciliation(
        materializedCount: {
          ...locallyAdvanced.map((entry) => entry.id),
          ...materialized.map((entry) => entry.id),
        }.length,
        failedSymbolCount: failedSymbolCount,
        unsupportedSymbolCount: unsupportedSymbolCount,
        partialSymbolCount: partialSymbolCount,
        staleSymbolCount: staleSymbolCount,
      );
    });

final watchlistSimulationObservationsProvider = StreamProvider.autoDispose
    .family<List<WatchlistSimulationObservation>, String>((
      ref,
      simulationId,
    ) async* {
      final allocation = ref
          .watch(watchlistSimulationAllocationProvider(simulationId))
          .asData
          ?.value;
      final simulations = ref.watch(watchlistSimulationsProvider).asData?.value;
      final simulation = simulations
          ?.where((candidate) => candidate.id == simulationId)
          .firstOrNull;
      if (allocation == null || !allocation.isUsable || simulation == null) {
        yield const <WatchlistSimulationObservation>[];
        return;
      }
      final baselineUtc = simulation.baselineAt.toUtc();
      String twoDigits(int part) => part.toString().padLeft(2, '0');
      final baselineDay =
          '${baselineUtc.year.toString().padLeft(4, '0')}-'
          '${twoDigits(baselineUtc.month)}-${twoDigits(baselineUtc.day)}';
      final repository = await ref.watch(
        watchlistSimulationRepositoryProvider.future,
      );
      final ownerUserId = await ref.watch(currentUserIdProvider)();
      yield* repository
          .watchObservations(
            ownerUserId: ownerUserId,
            simulationId: simulationId,
          )
          .map(
            (observations) => observations
                .where(
                  (observation) =>
                      allocation.validAllocationBasisKeys.contains(
                        observation.allocationBasisKey,
                      ) ||
                      (observation.allocationBasisKey == null &&
                          observation.observationDay == baselineDay),
                )
                .toList(growable: false),
          );
    });

class WatchlistSimulationObservationRequest {
  const WatchlistSimulationObservationRequest({
    required this.simulation,
    required this.observedAt,
    required this.weightedDailyChange,
    required this.pricedWeight,
    required this.missingQuoteWeight,
    required this.allocationBasisKey,
  });

  final WatchlistSimulation simulation;
  final DateTime observedAt;
  final Decimal weightedDailyChange;
  final Decimal pricedWeight;
  final Decimal missingQuoteWeight;
  final String allocationBasisKey;
}

typedef WatchlistSimulationObservationRecorder = Future<void> Function(
  WatchlistSimulationObservationRequest request,
);

final watchlistSimulationObservationRecorderProvider =
    Provider<WatchlistSimulationObservationRecorder>((ref) {
      return (request) async {
        final repository = await ref.read(
          watchlistSimulationRepositoryProvider.future,
        );
        await repository.recordObservation(
          simulation: request.simulation,
          observedAt: request.observedAt,
          weightedDailyChange: request.weightedDailyChange,
          pricedWeight: request.pricedWeight,
          missingQuoteWeight: request.missingQuoteWeight,
          allocationBasisKey: request.allocationBasisKey,
        );
      };
    });
