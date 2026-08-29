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
    planId: action.planId,
    source: action.source,
    createdAt: action.createdAt,
    completedAt: completedAt,
    sync: sync,
  );
}

/// Moves open child actions back to Inbox when their container is closed or
/// deleted.
///
/// Keeping the action open is useful, but keeping a relation to a container
/// that is no longer in the active inventory makes the action very easy to
/// lose. The previous action snapshot is returned so a lifecycle undo can
/// restore the relation without guessing it later.
Future<List<ExecutionAction>> _detachOpenActionsToInbox({
  required AppDatabase db,
  required OutboxStore outbox,
  required String ownerUserId,
  String? planId,
  required SyncMeta sync,
}) async {
  final q = db.select(db.executionActions)
    ..where((t) => t.ownerUserId.equals(ownerUserId))
    ..where((t) => t.deletedAt.isNull())
    ..where(
      (t) => t.status.isIn(<String>[
        ExecutionActionStatus.todo.wire,
        ExecutionActionStatus.doing.wire,
        ExecutionActionStatus.blocked.wire,
      ]),
    );
  if (planId != null) {
    q.where((t) => t.planId.equals(planId));
  }

  final rows = await q.get();
  final actions = rows.map(executionActionFromRow).toList(growable: false);
  for (final action in actions) {
    final moved = action.copyWith(planId: null, sync: sync);
    await db
        .into(db.executionActions)
        .insert(
          executionActionCompanion(moved),
          mode: InsertMode.insertOrReplace,
        );
    await outbox.enqueue(
      table: ExecutionRepository._actionsTable,
      rowId: moved.id,
    );
  }
  return actions;
}

ExecutionProgressEntry _tombstonedProgress(
  ExecutionProgressEntry progress,
  SyncMeta sync,
) {
  return ExecutionProgressEntry(
    id: progress.id,
    actionId: progress.actionId,
    planId: progress.planId,
    kind: progress.kind,
    note: progress.note,
    createdAt: progress.createdAt,
    sync: _executionTombstone(sync),
  );
}
