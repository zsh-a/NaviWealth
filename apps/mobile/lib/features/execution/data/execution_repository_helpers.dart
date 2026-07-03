part of 'execution_repository.dart';

SyncMeta _executionTombstone(SyncMeta sync) {
  return sync.copyWith(deletedAt: sync.updatedAt);
}

ExecutionAction _executionActionWithStatus(
  ExecutionAction action, {
  required ExecutionActionStatus status,
  required SyncMeta sync,
}) {
  final completedAt = switch (status) {
    ExecutionActionStatus.done ||
    ExecutionActionStatus.dropped => sync.updatedAt,
    ExecutionActionStatus.todo ||
    ExecutionActionStatus.doing ||
    ExecutionActionStatus.blocked => null,
  };
  return ExecutionAction(
    id: action.id,
    title: action.title,
    note: action.note,
    status: status,
    priority: action.priority,
    dueAt: action.dueAt,
    scheduledFor: action.scheduledFor,
    projectId: action.projectId,
    commitmentId: action.commitmentId,
    source: action.source,
    createdAt: action.createdAt,
    completedAt: completedAt,
    sync: sync,
  );
}
