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

final executionClosedActionsProvider =
    StreamProvider.autoDispose<List<ExecutionAction>>((ref) async* {
      final ownerUserId = await ref.watch(executionOwnerUserIdProvider.future);
      final repository = await ref.watch(executionRepositoryProvider.future);
      yield* repository.watchClosedActions(ownerUserId: ownerUserId);
    });

final executionActionByIdProvider = FutureProvider.autoDispose
    .family<ExecutionAction?, String>((ref, id) async {
      final ownerUserId = await ref.watch(executionOwnerUserIdProvider.future);
      final repository = await ref.watch(executionRepositoryProvider.future);
      return repository.findAction(ownerUserId: ownerUserId, id: id);
    });

final executionActionDetailProvider = StreamProvider.autoDispose
    .family<ExecutionAction?, String>((ref, id) async* {
      final ownerUserId = await ref.watch(executionOwnerUserIdProvider.future);
      final repository = await ref.watch(executionRepositoryProvider.future);
      yield* repository.watchActionById(ownerUserId: ownerUserId, id: id);
    });

final executionPlansProvider = StreamProvider.autoDispose<List<ExecutionPlan>>((
  ref,
) async* {
  final ownerUserId = await ref.watch(executionOwnerUserIdProvider.future);
  final repository = await ref.watch(executionRepositoryProvider.future);
  yield* repository.watchActivePlans(ownerUserId: ownerUserId);
});

final executionClosedPlansProvider =
    StreamProvider.autoDispose<List<ExecutionPlan>>((ref) async* {
      final ownerUserId = await ref.watch(executionOwnerUserIdProvider.future);
      final repository = await ref.watch(executionRepositoryProvider.future);
      yield* repository.watchClosedPlans(ownerUserId: ownerUserId);
    });

final executionPlanByIdProvider = FutureProvider.autoDispose
    .family<ExecutionPlan?, String>((ref, id) async {
      final ownerUserId = await ref.watch(executionOwnerUserIdProvider.future);
      final repository = await ref.watch(executionRepositoryProvider.future);
      return repository.findPlan(ownerUserId: ownerUserId, id: id);
    });

final executionPlanDetailProvider = StreamProvider.autoDispose
    .family<ExecutionPlan?, String>((ref, id) async* {
      final ownerUserId = await ref.watch(executionOwnerUserIdProvider.future);
      final repository = await ref.watch(executionRepositoryProvider.future);
      yield* repository.watchPlanById(ownerUserId: ownerUserId, id: id);
    });

final executionActionsForPlanProvider = StreamProvider.autoDispose
    .family<List<ExecutionAction>, String>((ref, id) async* {
      final ownerUserId = await ref.watch(executionOwnerUserIdProvider.future);
      final repository = await ref.watch(executionRepositoryProvider.future);
      yield* repository.watchActionsForPlan(
        ownerUserId: ownerUserId,
        planId: id,
      );
    });

final executionRecentProgressProvider =
    StreamProvider.autoDispose<List<ExecutionProgressEntry>>((ref) async* {
      final ownerUserId = await ref.watch(executionOwnerUserIdProvider.future);
      final repository = await ref.watch(executionRepositoryProvider.future);
      yield* repository.watchRecentProgress(ownerUserId: ownerUserId);
    });

final executionProgressForActionProvider = StreamProvider.autoDispose
    .family<List<ExecutionProgressEntry>, String>((ref, id) async* {
      final ownerUserId = await ref.watch(executionOwnerUserIdProvider.future);
      final repository = await ref.watch(executionRepositoryProvider.future);
      yield* repository.watchProgressForAction(
        ownerUserId: ownerUserId,
        actionId: id,
      );
    });

final executionProgressForPlanProvider = StreamProvider.autoDispose
    .family<List<ExecutionProgressEntry>, String>((ref, id) async* {
      final ownerUserId = await ref.watch(executionOwnerUserIdProvider.future);
      final repository = await ref.watch(executionRepositoryProvider.future);
      yield* repository.watchProgressForPlan(
        ownerUserId: ownerUserId,
        planId: id,
      );
    });

class ExecutionRelations {
  const ExecutionRelations({required this.actions, required this.plans});

  final Map<String, ExecutionAction> actions;
  final Map<String, ExecutionPlan> plans;

  String? actionLabel(String? id) =>
      id == null || id.isEmpty ? null : actions[id]?.title ?? id;

  String? planLabel(String? id) =>
      id == null || id.isEmpty ? null : plans[id]?.title ?? id;
}

typedef ExecutionReviewRelations = ExecutionRelations;

final executionActionRelationsProvider =
    FutureProvider.autoDispose<ExecutionRelations>((ref) async {
      final ownerUserId = await ref.watch(executionOwnerUserIdProvider.future);
      final repository = await ref.watch(executionRepositoryProvider.future);
      final actionsAsync = ref.watch(executionOpenActionsProvider);
      final List<ExecutionAction> actions =
          actionsAsync.maybeWhen(data: (value) => value, orElse: () => null) ??
          await ref.watch(executionOpenActionsProvider.future);
      final planIds = <String>{};
      for (final action in actions) {
        final planId = action.planId;
        if (planId != null && planId.isNotEmpty) {
          planIds.add(planId);
        }
      }

      final plans = await repository.listPlansByIds(
        ownerUserId: ownerUserId,
        ids: planIds,
      );
      return ExecutionRelations(
        actions: {for (final action in actions) action.id: action},
        plans: {for (final plan in plans) plan.id: plan},
      );
    });

final executionReviewRelationsProvider =
    FutureProvider.autoDispose<ExecutionReviewRelations>((ref) async {
      final ownerUserId = await ref.watch(executionOwnerUserIdProvider.future);
      final repository = await ref.watch(executionRepositoryProvider.future);
      final progressAsync = ref.watch(executionRecentProgressProvider);
      final closedActionsAsync = ref.watch(executionClosedActionsProvider);
      final List<ExecutionProgressEntry> progress =
          progressAsync.maybeWhen(data: (value) => value, orElse: () => null) ??
          await ref.watch(executionRecentProgressProvider.future);
      final List<ExecutionAction> closedActions =
          closedActionsAsync.maybeWhen(
            data: (value) => value,
            orElse: () => null,
          ) ??
          await ref.watch(executionClosedActionsProvider.future);
      final actionIds = <String>{};
      final planIds = <String>{};
      for (final entry in progress) {
        final actionId = entry.actionId;
        if (actionId != null && actionId.isNotEmpty) actionIds.add(actionId);
        final planId = entry.planId;
        if (planId != null && planId.isNotEmpty) {
          planIds.add(planId);
        }
      }
      for (final action in closedActions) {
        final planId = action.planId;
        if (planId != null && planId.isNotEmpty) {
          planIds.add(planId);
        }
      }

      final actions = await repository.listActionsByIds(
        ownerUserId: ownerUserId,
        ids: actionIds,
      );
      final plans = await repository.listPlansByIds(
        ownerUserId: ownerUserId,
        ids: planIds,
      );
      return ExecutionRelations(
        actions: {
          for (final action in actions) action.id: action,
          for (final action in closedActions) action.id: action,
        },
        plans: {for (final plan in plans) plan.id: plan},
      );
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
