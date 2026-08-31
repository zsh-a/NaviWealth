import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naviwealth/core/persistence/providers.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/core/sync/outbox_provider.dart';

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
