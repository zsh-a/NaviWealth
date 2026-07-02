import 'package:drift/drift.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/execution/domain/execution_models.dart';

ExecutionProjectsCompanion executionProjectCompanion(ExecutionProject project) {
  return ExecutionProjectsCompanion.insert(
    id: project.id,
    title: project.title,
    description: Value(project.description),
    status: Value(project.status.wire),
    horizon: Value(project.horizon.wire),
    targetDate: Value(project.targetDate),
    sourceDomain: Value(project.source.domain),
    sourceRowFamily: Value(project.source.rowFamily),
    sourceRowId: Value(project.source.rowId),
    sourceLabelSnapshot: Value(project.source.labelSnapshot),
    createdAt: project.createdAt,
    completedAt: Value(project.completedAt),
    ownerUserId: project.sync.ownerUserId,
    updatedAt: project.sync.updatedAt,
    updatedByDevice: project.sync.updatedByDevice,
    hlc: project.sync.hlc,
    deletedAt: Value(project.sync.deletedAt),
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
    projectId: Value(action.projectId),
    commitmentId: Value(action.commitmentId),
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

ExecutionCommitmentsCompanion executionCommitmentCompanion(
  ExecutionCommitment commitment,
) {
  return ExecutionCommitmentsCompanion.insert(
    id: commitment.id,
    title: commitment.title,
    description: Value(commitment.description),
    status: Value(commitment.status.wire),
    horizon: Value(commitment.horizon.wire),
    targetDate: Value(commitment.targetDate),
    projectId: Value(commitment.projectId),
    sourceDomain: Value(commitment.source.domain),
    sourceRowFamily: Value(commitment.source.rowFamily),
    sourceRowId: Value(commitment.source.rowId),
    sourceLabelSnapshot: Value(commitment.source.labelSnapshot),
    createdAt: commitment.createdAt,
    completedAt: Value(commitment.completedAt),
    ownerUserId: commitment.sync.ownerUserId,
    updatedAt: commitment.sync.updatedAt,
    updatedByDevice: commitment.sync.updatedByDevice,
    hlc: commitment.sync.hlc,
    deletedAt: Value(commitment.sync.deletedAt),
  );
}

ExecutionProgressEntriesCompanion executionProgressCompanion(
  ExecutionProgressEntry progress,
) {
  return ExecutionProgressEntriesCompanion.insert(
    id: progress.id,
    actionId: Value(progress.actionId),
    projectId: Value(progress.projectId),
    commitmentId: Value(progress.commitmentId),
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
    projectId: r.projectId,
    commitmentId: r.commitmentId,
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

ExecutionProject executionProjectFromRow(ExecutionProjectRow r) {
  return ExecutionProject(
    id: r.id,
    title: r.title,
    description: r.description,
    status: ExecutionProjectStatus.parse(r.status),
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

ExecutionCommitment executionCommitmentFromRow(ExecutionCommitmentRow r) {
  return ExecutionCommitment(
    id: r.id,
    title: r.title,
    description: r.description,
    status: ExecutionCommitmentStatus.parse(r.status),
    horizon: ExecutionHorizon.parse(r.horizon),
    targetDate: r.targetDate,
    projectId: r.projectId,
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
    projectId: r.projectId,
    commitmentId: r.commitmentId,
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
