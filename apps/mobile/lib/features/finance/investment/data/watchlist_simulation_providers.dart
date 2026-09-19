import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naviwealth/core/persistence/providers.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/core/sync/outbox_provider.dart';
import 'package:naviwealth/features/finance/data/market/market_data_providers.dart';
import 'package:naviwealth/features/finance/investment/data/event_timeline_providers.dart';
import 'package:naviwealth/features/finance/investment/data/watchlist_providers.dart';
import 'package:naviwealth/features/finance/investment/data/watchlist_repository.dart';
import 'package:naviwealth/features/finance/market/domain/corporate_action_provider.dart';
import 'package:naviwealth/features/finance/market/domain/historical_bar.dart';
import 'package:naviwealth/features/finance/market/domain/market_corporate_action.dart';
import 'package:naviwealth/features/finance/market/domain/market_data_service.dart';

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
                // Reference-only rows may predate allocation lineage; a
                // paper-valued row must be tied to a concrete lineage.
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
      // Make the read model self-healing for non-UI consumers as well. The
      // live recorder can write independently because backfill only fills
      // missing completed days and rebuilds the chain transactionally.
      ref.watch(watchlistSimulationHistoricalBackfillProvider(simulationId));
      final allocation = ref
          .watch(watchlistSimulationAllocationProvider(simulationId))
          .asData
          ?.value;
      if (allocation == null || !allocation.isUsable) {
        yield const <WatchlistSimulationObservation>[];
        return;
      }
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
                      watchlistSimulationObservationIsInAllocationLineage(
                        allocationBasisKey: observation.allocationBasisKey,
                        validAllocationBasisKeys:
                            allocation.validAllocationBasisKeys,
                      ),
                )
                .toList(growable: false),
          );
    });

/// Fills missed UTC days from the simulation baseline through yesterday.
///
/// The current day still comes from the live quote recorder. Keeping the
/// historical and live paths separate avoids mixing an unfinished intraday
/// bar into a completed daily return while sharing the repository's single
/// observation-chain rebuild.
final watchlistSimulationHistoricalBackfillProvider = FutureProvider.autoDispose
    .family<int, String>((ref, simulationId) async {
      final simulations = await ref.watch(watchlistSimulationsProvider.future);
      final simulation = simulations
          .where((candidate) => candidate.id == simulationId)
          .firstOrNull;
      if (simulation == null) return 0;

      final allocation = await ref.watch(
        watchlistSimulationAllocationProvider(simulationId).future,
      );
      final allocationBasisKey = allocation.allocationBasisKey;
      if (!allocation.isUsable || allocationBasisKey == null) return 0;

      final positions = allocation.positions;
      if (positions.isEmpty) return 0;
      final items = await ref.watch(watchlistItemsProvider.future);
      final itemById = {for (final item in items) item.id: item};
      final market = await ref.watch(marketDataServiceProvider.future);
      final baselineDay = _utcDay(simulation.baselineAt);
      final today = _utcDay(ref.watch(clockProvider).now().toUtc());
      final lastCompletedDay = today.subtract(const Duration(days: 1));
      if (!baselineDay.isBefore(lastCompletedDay)) return 0;

      final returnsByItemId = <String, Map<DateTime, Decimal>>{};
      final dates = <DateTime>{};
      for (final position in positions) {
        final item = itemById[position.watchlistItemId];
        if (item == null) continue;
        final response = await _tryHistoricalResponse(
          market,
          item,
          from: baselineDay.subtract(const Duration(days: 1)),
          to: lastCompletedDay,
        );
        if (response == null) continue;
        final closes = <DateTime, Decimal>{};
        for (final bar in response.data) {
          final day = _utcDay(bar.asOf);
          if (day.isBefore(baselineDay.subtract(const Duration(days: 1))) ||
              day.isAfter(lastCompletedDay) ||
              bar.symbol.toUpperCase() != item.symbol.toUpperCase()) {
            continue;
          }
          final close =
              bar.adjustedClose != null && bar.adjustedClose! > Decimal.zero
              ? bar.adjustedClose!
              : bar.close;
          if (close > Decimal.zero) closes[day] = close;
        }
        if (closes.isEmpty) continue;
        final orderedDays = closes.keys.toList()..sort();
        Decimal? previous;
        final dailyReturns = <DateTime, Decimal>{};
        for (final day in orderedDays) {
          final close = closes[day]!;
          if (previous != null && day.isAfter(baselineDay)) {
            final ratio = (close / previous).toDecimal(
              scaleOnInfinitePrecision: 18,
            );
            dailyReturns[day] = ratio - Decimal.one;
            dates.add(day);
          }
          previous = close;
        }
        if (dailyReturns.isNotEmpty) {
          returnsByItemId[position.watchlistItemId] = dailyReturns;
        }
      }
      if (dates.isEmpty) return 0;

      final inputs = <WatchlistSimulationObservationInput>[];
      final orderedDates = dates.toList()..sort();
      for (final day in orderedDates) {
        var weightedDailyChange = Decimal.zero;
        var pricedWeight = Decimal.zero;
        var missingQuoteWeight = Decimal.zero;
        for (final position in positions) {
          final change = returnsByItemId[position.watchlistItemId]?[day];
          if (change == null) {
            missingQuoteWeight += position.targetWeight;
          } else {
            pricedWeight += position.targetWeight;
            weightedDailyChange += position.targetWeight * change;
          }
        }
        if (pricedWeight <= Decimal.zero) continue;
        inputs.add(
          WatchlistSimulationObservationInput(
            observedAt: DateTime.utc(day.year, day.month, day.day, 23, 59, 59),
            weightedDailyChange: weightedDailyChange,
            pricedWeight: pricedWeight,
            missingQuoteWeight: missingQuoteWeight,
          ),
        );
      }
      if (inputs.isEmpty) return 0;

      final repository = await ref.watch(
        watchlistSimulationRepositoryProvider.future,
      );
      return repository.mergeObservationInputs(
        simulation: simulation,
        inputs: inputs,
        allocationBasisKey: allocationBasisKey,
      );
    });

Future<MarketResponse<List<HistoricalBar>>?> _tryHistoricalResponse(
  MarketDataService market,
  WatchlistItem item, {
  required DateTime from,
  required DateTime to,
}) async {
  try {
    return await market.getHistorical(
      item.symbol,
      from: from,
      to: to,
      market: item.market,
    );
  } on Object {
    return null;
  }
}

DateTime _utcDay(DateTime value) {
  final utc = value.toUtc();
  return DateTime.utc(utc.year, utc.month, utc.day);
}

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
