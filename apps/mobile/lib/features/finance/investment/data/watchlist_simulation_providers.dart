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
      final repository = await ref.watch(
        watchlistSimulationRepositoryProvider.future,
      );
      final ownerUserId = await ref.watch(currentUserIdProvider)();
      yield* repository.watchActionEntries(
        ownerUserId: ownerUserId,
        simulationId: simulationId,
      );
    });

class WatchlistSimulationActionReconciliation {
  const WatchlistSimulationActionReconciliation({
    required this.materializedCount,
    required this.failedSymbolCount,
    required this.unsupportedSymbolCount,
  });

  final int materializedCount;
  final int failedSymbolCount;
  final int unsupportedSymbolCount;
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
      final positions = await ref.watch(
        watchlistSimulationPositionsProvider(simulationId).future,
      );
      final items = await ref.watch(watchlistItemsProvider.future);
      final itemById = {for (final item in items) item.id: item};
      final corporateActions = await ref.watch(
        corporateActionsServiceProvider.future,
      );
      final actionsByItemId = <String, Iterable<MarketCorporateAction>>{};
      var failedSymbolCount = 0;
      var unsupportedSymbolCount = 0;
      for (final position in positions) {
        final item = itemById[position.watchlistItemId];
        if (item == null) continue;
        final result = await corporateActions.fetchForSymbol(
          item.symbol,
          market: item.market,
        );
        if (result.hasUsableData) {
          actionsByItemId[item.id] = result.actions;
        } else if (result.disposition ==
            CorporateActionFetchDisposition.unsupported) {
          unsupportedSymbolCount++;
        } else {
          failedSymbolCount++;
        }
      }
      final repository = await ref.watch(
        watchlistSimulationRepositoryProvider.future,
      );
      final materialized = await repository.materializeDividendReferences(
        simulation: simulation,
        actionsByWatchlistItemId: actionsByItemId,
      );
      return WatchlistSimulationActionReconciliation(
        materializedCount: materialized.length,
        failedSymbolCount: failedSymbolCount,
        unsupportedSymbolCount: unsupportedSymbolCount,
      );
    });

final watchlistSimulationObservationsProvider = StreamProvider.autoDispose
    .family<List<WatchlistSimulationObservation>, String>((
      ref,
      simulationId,
    ) async* {
      final repository = await ref.watch(
        watchlistSimulationRepositoryProvider.future,
      );
      final ownerUserId = await ref.watch(currentUserIdProvider)();
      yield* repository.watchObservations(
        ownerUserId: ownerUserId,
        simulationId: simulationId,
      );
    });

class WatchlistSimulationObservationRequest {
  const WatchlistSimulationObservationRequest({
    required this.simulation,
    required this.observedAt,
    required this.weightedDailyChange,
    required this.pricedWeight,
    required this.missingQuoteWeight,
  });

  final WatchlistSimulation simulation;
  final DateTime observedAt;
  final Decimal weightedDailyChange;
  final Decimal pricedWeight;
  final Decimal missingQuoteWeight;
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
        );
      };
    });
