import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/persistence/providers.dart';
import '../../../core/sync/mutation_context.dart';
import '../../../core/sync/outbox_provider.dart';
import '../../../core/sync/sync_meta.dart';
import '../domain/execution_models.dart';
import 'execution_repository.dart';

const Uuid kExecutionUuid = Uuid();

final executionRepositoryProvider = FutureProvider<ExecutionRepository>((
  ref,
) async {
  final db = await ref.watch(appDatabaseProvider.future);
  final outbox = await ref.watch(outboxStoreProvider.future);
  return ExecutionRepository(db: db, outbox: outbox);
});

final executionOwnerUserIdProvider = FutureProvider.autoDispose<String>((ref) {
  return ref.watch(currentUserIdProvider)();
});

final executionTodayActionsProvider =
    StreamProvider.autoDispose<List<ExecutionAction>>((ref) async* {
      final ownerUserId = await ref.watch(executionOwnerUserIdProvider.future);
      final repository = await ref.watch(executionRepositoryProvider.future);
      yield* repository.watchTodayActions(
        ownerUserId: ownerUserId,
        asOf: DateTime.now(),
      );
    });

final executionOpenActionsProvider =
    StreamProvider.autoDispose<List<ExecutionAction>>((ref) async* {
      final ownerUserId = await ref.watch(executionOwnerUserIdProvider.future);
      final repository = await ref.watch(executionRepositoryProvider.future);
      yield* repository.watchOpenActions(ownerUserId: ownerUserId);
    });

final executionProjectsProvider =
    StreamProvider.autoDispose<List<ExecutionProject>>((ref) async* {
      final ownerUserId = await ref.watch(executionOwnerUserIdProvider.future);
      final repository = await ref.watch(executionRepositoryProvider.future);
      yield* repository.watchActiveProjects(ownerUserId: ownerUserId);
    });

final executionCommitmentsProvider =
    StreamProvider.autoDispose<List<ExecutionCommitment>>((ref) async* {
      final ownerUserId = await ref.watch(executionOwnerUserIdProvider.future);
      final repository = await ref.watch(executionRepositoryProvider.future);
      yield* repository.watchActiveCommitments(ownerUserId: ownerUserId);
    });

final executionRecentProgressProvider =
    StreamProvider.autoDispose<List<ExecutionProgressEntry>>((ref) async* {
      final ownerUserId = await ref.watch(executionOwnerUserIdProvider.future);
      final repository = await ref.watch(executionRepositoryProvider.future);
      yield* repository.watchRecentProgress(ownerUserId: ownerUserId);
    });

Future<SyncMeta> stampExecutionSync(WidgetRef ref) async {
  final stamper = await ref.read(mutationStamperProvider.future);
  final stamp = await stamper.stamp();
  return SyncMeta(
    ownerUserId: stamp.ownerUserId,
    updatedAt: stamp.now,
    updatedByDevice: stamp.deviceId,
    hlc: stamp.hlc,
  );
}
