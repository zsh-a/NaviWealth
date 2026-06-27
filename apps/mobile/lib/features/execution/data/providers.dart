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

final executionProjectsProvider =
    StreamProvider.autoDispose<List<ExecutionProject>>((ref) async* {
      final ownerUserId = await ref.watch(executionOwnerUserIdProvider.future);
      final repository = await ref.watch(executionRepositoryProvider.future);
      yield* repository.watchActiveProjects(ownerUserId: ownerUserId);
    });

final executionClosedProjectsProvider =
    StreamProvider.autoDispose<List<ExecutionProject>>((ref) async* {
      final ownerUserId = await ref.watch(executionOwnerUserIdProvider.future);
      final repository = await ref.watch(executionRepositoryProvider.future);
      yield* repository.watchClosedProjects(ownerUserId: ownerUserId);
    });

final executionProjectByIdProvider = FutureProvider.autoDispose
    .family<ExecutionProject?, String>((ref, id) async {
      final ownerUserId = await ref.watch(executionOwnerUserIdProvider.future);
      final repository = await ref.watch(executionRepositoryProvider.future);
      return repository.findProject(ownerUserId: ownerUserId, id: id);
    });

final executionCommitmentsProvider =
    StreamProvider.autoDispose<List<ExecutionCommitment>>((ref) async* {
      final ownerUserId = await ref.watch(executionOwnerUserIdProvider.future);
      final repository = await ref.watch(executionRepositoryProvider.future);
      yield* repository.watchActiveCommitments(ownerUserId: ownerUserId);
    });

final executionClosedCommitmentsProvider =
    StreamProvider.autoDispose<List<ExecutionCommitment>>((ref) async* {
      final ownerUserId = await ref.watch(executionOwnerUserIdProvider.future);
      final repository = await ref.watch(executionRepositoryProvider.future);
      yield* repository.watchClosedCommitments(ownerUserId: ownerUserId);
    });

final executionCommitmentByIdProvider = FutureProvider.autoDispose
    .family<ExecutionCommitment?, String>((ref, id) async {
      final ownerUserId = await ref.watch(executionOwnerUserIdProvider.future);
      final repository = await ref.watch(executionRepositoryProvider.future);
      return repository.findCommitment(ownerUserId: ownerUserId, id: id);
    });

final executionRecentProgressProvider =
    StreamProvider.autoDispose<List<ExecutionProgressEntry>>((ref) async* {
      final ownerUserId = await ref.watch(executionOwnerUserIdProvider.future);
      final repository = await ref.watch(executionRepositoryProvider.future);
      yield* repository.watchRecentProgress(ownerUserId: ownerUserId);
    });

class ExecutionRelations {
  const ExecutionRelations({
    required this.actions,
    required this.projects,
    required this.commitments,
  });

  final Map<String, ExecutionAction> actions;
  final Map<String, ExecutionProject> projects;
  final Map<String, ExecutionCommitment> commitments;

  String? actionLabel(String? id) =>
      id == null || id.isEmpty ? null : actions[id]?.title ?? id;

  String? projectLabel(String? id) =>
      id == null || id.isEmpty ? null : projects[id]?.title ?? id;

  String? commitmentLabel(String? id) =>
      id == null || id.isEmpty ? null : commitments[id]?.title ?? id;
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
      final projectIds = <String>{};
      final commitmentIds = <String>{};
      for (final action in actions) {
        final projectId = action.projectId;
        if (projectId != null && projectId.isNotEmpty) {
          projectIds.add(projectId);
        }
        final commitmentId = action.commitmentId;
        if (commitmentId != null && commitmentId.isNotEmpty) {
          commitmentIds.add(commitmentId);
        }
      }

      final projects = await repository.listProjectsByIds(
        ownerUserId: ownerUserId,
        ids: projectIds,
      );
      final commitments = await repository.listCommitmentsByIds(
        ownerUserId: ownerUserId,
        ids: commitmentIds,
      );
      return ExecutionRelations(
        actions: {for (final action in actions) action.id: action},
        projects: {for (final project in projects) project.id: project},
        commitments: {
          for (final commitment in commitments) commitment.id: commitment,
        },
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
      final projectIds = <String>{};
      final commitmentIds = <String>{};
      for (final entry in progress) {
        final actionId = entry.actionId;
        if (actionId != null && actionId.isNotEmpty) actionIds.add(actionId);
        final projectId = entry.projectId;
        if (projectId != null && projectId.isNotEmpty) {
          projectIds.add(projectId);
        }
        final commitmentId = entry.commitmentId;
        if (commitmentId != null && commitmentId.isNotEmpty) {
          commitmentIds.add(commitmentId);
        }
      }
      for (final action in closedActions) {
        final projectId = action.projectId;
        if (projectId != null && projectId.isNotEmpty) {
          projectIds.add(projectId);
        }
        final commitmentId = action.commitmentId;
        if (commitmentId != null && commitmentId.isNotEmpty) {
          commitmentIds.add(commitmentId);
        }
      }

      final actions = await repository.listActionsByIds(
        ownerUserId: ownerUserId,
        ids: actionIds,
      );
      final projects = await repository.listProjectsByIds(
        ownerUserId: ownerUserId,
        ids: projectIds,
      );
      final commitments = await repository.listCommitmentsByIds(
        ownerUserId: ownerUserId,
        ids: commitmentIds,
      );
      return ExecutionRelations(
        actions: {
          for (final action in actions) action.id: action,
          for (final action in closedActions) action.id: action,
        },
        projects: {for (final project in projects) project.id: project},
        commitments: {
          for (final commitment in commitments) commitment.id: commitment,
        },
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
