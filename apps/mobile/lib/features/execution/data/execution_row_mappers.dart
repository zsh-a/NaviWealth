import 'package:drift/drift.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/execution/domain/execution_models.dart';

ExecutionPlansCompanion executionPlanCompanion(ExecutionPlan plan) {
  return ExecutionPlansCompanion.insert(
    id: plan.id,
    title: plan.title,
    description: Value(plan.description),
    status: Value(plan.status.wire),
    horizon: Value(plan.horizon.wire),
    targetDate: Value(plan.targetDate),
    sourceDomain: Value(plan.source.domain),
    sourceRowFamily: Value(plan.source.rowFamily),
    sourceRowId: Value(plan.source.rowId),
    sourceLabelSnapshot: Value(plan.source.labelSnapshot),
    createdAt: plan.createdAt,
    completedAt: Value(plan.completedAt),
    ownerUserId: plan.sync.ownerUserId,
    updatedAt: plan.sync.updatedAt,
    updatedByDevice: plan.sync.updatedByDevice,
    hlc: plan.sync.hlc,
    deletedAt: Value(plan.sync.deletedAt),
  );
}

ExecutionActionsCompanion executionActionCompanion(ExecutionAction action) {
  return ExecutionActionsCompanion.insert(
    id: action.id,
    title: action.title,
    note: Value(action.note),
    status: Value(action.status.wire),
    priority: Value(action.priority.wire),
    dueAt: Value(action.dueAt),
    scheduledFor: Value(action.scheduledFor),
    planId: Value(action.planId),
    sourceDomain: Value(action.source.domain),
    sourceRowFamily: Value(action.source.rowFamily),
    sourceRowId: Value(action.source.rowId),
    sourceLabelSnapshot: Value(action.source.labelSnapshot),
    createdAt: action.createdAt,
    completedAt: Value(action.completedAt),
    ownerUserId: action.sync.ownerUserId,
    updatedAt: action.sync.updatedAt,
    updatedByDevice: action.sync.updatedByDevice,
    hlc: action.sync.hlc,
    deletedAt: Value(action.sync.deletedAt),
  );
}

ExecutionProgressEntriesCompanion executionProgressCompanion(
  ExecutionProgressEntry progress,
) {
  return ExecutionProgressEntriesCompanion.insert(
    id: progress.id,
    actionId: Value(progress.actionId),
    planId: Value(progress.planId),
    kind: Value(progress.kind.wire),
    note: progress.note,
    createdAt: progress.createdAt,
    ownerUserId: progress.sync.ownerUserId,
    updatedAt: progress.sync.updatedAt,
    updatedByDevice: progress.sync.updatedByDevice,
    hlc: progress.sync.hlc,
    deletedAt: Value(progress.sync.deletedAt),
  );
}

ExecutionAction executionActionFromRow(ExecutionActionRow r) {
  return ExecutionAction(
    id: r.id,
    title: r.title,
    note: r.note,
    status: ExecutionActionStatus.parse(r.status),
    priority: ExecutionPriority.parse(r.priority),
    dueAt: r.dueAt,
    scheduledFor: r.scheduledFor,
    planId: r.planId,
    source: ExecutionSourceRef(
      domain: r.sourceDomain,
      rowFamily: r.sourceRowFamily,
      rowId: r.sourceRowId,
      labelSnapshot: r.sourceLabelSnapshot,
    ),
    createdAt: r.createdAt,
    completedAt: r.completedAt,
    sync: _syncFromRow(
      ownerUserId: r.ownerUserId,
      updatedAt: r.updatedAt,
      updatedByDevice: r.updatedByDevice,
      hlc: r.hlc,
      deletedAt: r.deletedAt,
    ),
  );
}

ExecutionPlan executionPlanFromRow(ExecutionPlanRow r) {
  return ExecutionPlan(
    id: r.id,
    title: r.title,
    description: r.description,
    status: ExecutionPlanStatus.parse(r.status),
    horizon: ExecutionHorizon.parse(r.horizon),
    targetDate: r.targetDate,
    source: ExecutionSourceRef(
      domain: r.sourceDomain,
      rowFamily: r.sourceRowFamily,
      rowId: r.sourceRowId,
      labelSnapshot: r.sourceLabelSnapshot,
    ),
    createdAt: r.createdAt,
    completedAt: r.completedAt,
    sync: _syncFromRow(
      ownerUserId: r.ownerUserId,
      updatedAt: r.updatedAt,
      updatedByDevice: r.updatedByDevice,
      hlc: r.hlc,
      deletedAt: r.deletedAt,
    ),
  );
}

ExecutionProgressEntry executionProgressFromRow(ExecutionProgressEntryRow r) {
  return ExecutionProgressEntry(
    id: r.id,
    actionId: r.actionId,
    planId: r.planId,
    kind: ExecutionProgressKind.parse(r.kind),
    note: r.note,
    createdAt: r.createdAt,
    sync: _syncFromRow(
      ownerUserId: r.ownerUserId,
      updatedAt: r.updatedAt,
      updatedByDevice: r.updatedByDevice,
      hlc: r.hlc,
      deletedAt: r.deletedAt,
    ),
  );
}

SyncMeta _syncFromRow({
  required String ownerUserId,
  required DateTime updatedAt,
  required String updatedByDevice,
  required Hlc hlc,
  required DateTime? deletedAt,
}) {
  return SyncMeta(
    ownerUserId: ownerUserId,
    updatedAt: updatedAt,
    updatedByDevice: updatedByDevice,
    hlc: hlc,
    deletedAt: deletedAt,
  );
}
