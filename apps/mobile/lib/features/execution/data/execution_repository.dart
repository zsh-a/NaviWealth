/// ExecutionOS repository.
///
/// Owns Drift access for actions, commitments, and progress entries. Callers
/// provide stamped sync metadata; the repository performs the write and
/// enqueues the changed row for sync.
library;

import 'package:drift/drift.dart' hide Column;

import '../../../core/persistence/app_database.dart';
import '../../../core/sync/hlc.dart';
import '../../../core/sync/op_outbox.dart';
import '../../../core/sync/sync_meta.dart';
import '../domain/execution_models.dart';

enum ExecutionEntryKind {
  project('execution_projects'),
  action('execution_actions'),
  commitment('execution_commitments'),
  progressEntry('execution_progress_entries');

  const ExecutionEntryKind(this.tableName);
  final String tableName;
}

class ExecutionRepository {
  ExecutionRepository({required AppDatabase db, required OutboxStore outbox})
    : _db = db,
      _outbox = outbox;

  final AppDatabase _db;
  final OutboxStore _outbox;

  static const String _projectsTable = 'execution_projects';
  static const String _actionsTable = 'execution_actions';
  static const String _commitmentsTable = 'execution_commitments';
  static const String _progressTable = 'execution_progress_entries';

  Future<void> _upsertAndEnqueue<R>(
    TableInfo<Table, R> table,
    Insertable<R> companion, {
    required String tableName,
    required String rowId,
  }) async {
    await _db.transaction(() async {
      await _db.into(table).insert(companion, mode: InsertMode.insertOrReplace);
      await _outbox.enqueue(table: tableName, rowId: rowId);
    });
  }

  Stream<List<ExecutionAction>> watchTodayActions({
    required String ownerUserId,
    required DateTime asOf,
    int limit = 100,
  }) {
    final endOfToday = DateTime(asOf.year, asOf.month, asOf.day + 1);
    final q = _db.select(_db.executionActions)
      ..where((t) => t.ownerUserId.equals(ownerUserId))
      ..where((t) => t.deletedAt.isNull())
      ..where(
        (t) =>
            t.status.isIn(<String>[
              ExecutionActionStatus.todo.wire,
              ExecutionActionStatus.doing.wire,
              ExecutionActionStatus.blocked.wire,
            ]) &
            (t.status.equals(ExecutionActionStatus.doing.wire) |
                t.status.equals(ExecutionActionStatus.blocked.wire) |
                t.scheduledFor.isSmallerThanValue(endOfToday) |
                t.dueAt.isSmallerThanValue(endOfToday) |
                t.priority.equals(ExecutionPriority.high.wire)),
      )
      ..orderBy([
        (t) => OrderingTerm(
          expression: t.status.equals(ExecutionActionStatus.blocked.wire),
          mode: OrderingMode.desc,
        ),
        (t) => OrderingTerm(
          expression: t.priority.equals(ExecutionPriority.high.wire),
          mode: OrderingMode.desc,
        ),
        (t) => OrderingTerm(expression: t.dueAt, mode: OrderingMode.asc),
        (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
      ])
      ..limit(limit);
    return q.watch().map((rows) => rows.map(_actionFromRow).toList());
  }

  Stream<List<ExecutionProject>> watchActiveProjects({
    required String ownerUserId,
    int limit = 100,
  }) {
    final q = _db.select(_db.executionProjects)
      ..where((t) => t.ownerUserId.equals(ownerUserId))
      ..where((t) => t.deletedAt.isNull())
      ..where(
        (t) => t.status.isIn(<String>[
          ExecutionProjectStatus.active.wire,
          ExecutionProjectStatus.paused.wire,
        ]),
      )
      ..orderBy([
        (t) => OrderingTerm(expression: t.targetDate, mode: OrderingMode.asc),
        (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
      ])
      ..limit(limit);
    return q.watch().map((rows) => rows.map(_projectFromRow).toList());
  }

  Stream<List<ExecutionProject>> watchClosedProjects({
    required String ownerUserId,
    int limit = 100,
  }) {
    final q = _db.select(_db.executionProjects)
      ..where((t) => t.ownerUserId.equals(ownerUserId))
      ..where((t) => t.deletedAt.isNull())
      ..where(
        (t) => t.status.isIn(<String>[
          ExecutionProjectStatus.completed.wire,
          ExecutionProjectStatus.archived.wire,
        ]),
      )
      ..orderBy([
        (t) => OrderingTerm(expression: t.completedAt, mode: OrderingMode.desc),
        (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
      ])
      ..limit(limit);
    return q.watch().map((rows) => rows.map(_projectFromRow).toList());
  }

  Future<List<ExecutionProject>> listActiveProjects({
    required String ownerUserId,
    int limit = 100,
  }) async {
    final q = _db.select(_db.executionProjects)
      ..where((t) => t.ownerUserId.equals(ownerUserId))
      ..where((t) => t.deletedAt.isNull())
      ..where(
        (t) => t.status.isIn(<String>[
          ExecutionProjectStatus.active.wire,
          ExecutionProjectStatus.paused.wire,
        ]),
      )
      ..orderBy([
        (t) => OrderingTerm(expression: t.targetDate, mode: OrderingMode.asc),
        (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
      ])
      ..limit(limit);
    final rows = await q.get();
    return rows.map(_projectFromRow).toList();
  }

  Stream<List<ExecutionProject>> watchProjectsForMemoryIndex({
    required String ownerUserId,
    int limit = 500,
  }) {
    final q = _db.select(_db.executionProjects)
      ..where((t) => t.ownerUserId.equals(ownerUserId))
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([
        (t) => OrderingTerm(expression: t.updatedAt, mode: OrderingMode.desc),
        (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
      ])
      ..limit(limit);
    return q.watch().map((rows) => rows.map(_projectFromRow).toList());
  }

  Future<void> upsertProject(ExecutionProject project) {
    return _upsertAndEnqueue(
      _db.executionProjects,
      _projectCompanion(project),
      tableName: _projectsTable,
      rowId: project.id,
    );
  }

  Future<void> softDeleteProject({
    required ExecutionProject project,
    required SyncMeta sync,
  }) {
    final tombstone = sync.copyWith(deletedAt: sync.updatedAt);
    return upsertProject(
      ExecutionProject(
        id: project.id,
        title: project.title,
        description: project.description,
        status: project.status,
        horizon: project.horizon,
        targetDate: project.targetDate,
        source: project.source,
        createdAt: project.createdAt,
        completedAt: project.completedAt,
        sync: tombstone,
      ),
    );
  }

  Future<void> updateProjectStatus({
    required ExecutionProject project,
    required ExecutionProjectStatus status,
    required SyncMeta sync,
  }) {
    return upsertProject(
      _projectWithStatus(project, status: status, sync: sync),
    );
  }

  Future<ExecutionProject?> findProject({
    required String ownerUserId,
    required String id,
  }) async {
    final row =
        await (_db.select(_db.executionProjects)..where(
              (t) => t.id.equals(id) & t.ownerUserId.equals(ownerUserId),
            ))
            .getSingleOrNull();
    return row == null ? null : _projectFromRow(row);
  }

  Future<List<ExecutionProject>> listProjectsByIds({
    required String ownerUserId,
    required Set<String> ids,
  }) async {
    if (ids.isEmpty) return const <ExecutionProject>[];
    final q = _db.select(_db.executionProjects)
      ..where(
        (t) =>
            t.ownerUserId.equals(ownerUserId) &
            t.id.isIn(ids.toList(growable: false)),
      );
    final rows = await q.get();
    return rows.map(_projectFromRow).toList(growable: false);
  }

  Stream<List<ExecutionAction>> watchOpenActions({
    required String ownerUserId,
    int limit = 200,
  }) {
    final q = _db.select(_db.executionActions)
      ..where((t) => t.ownerUserId.equals(ownerUserId))
      ..where((t) => t.deletedAt.isNull())
      ..where(
        (t) => t.status.isIn(<String>[
          ExecutionActionStatus.todo.wire,
          ExecutionActionStatus.doing.wire,
          ExecutionActionStatus.blocked.wire,
        ]),
      )
      ..orderBy([
        (t) => OrderingTerm(
          expression: t.status.equals(ExecutionActionStatus.blocked.wire),
          mode: OrderingMode.desc,
        ),
        (t) => OrderingTerm(
          expression: t.priority.equals(ExecutionPriority.high.wire),
          mode: OrderingMode.desc,
        ),
        (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
      ])
      ..limit(limit);
    return q.watch().map((rows) => rows.map(_actionFromRow).toList());
  }

  Stream<List<ExecutionAction>> watchClosedActions({
    required String ownerUserId,
    int limit = 100,
  }) {
    final q = _db.select(_db.executionActions)
      ..where((t) => t.ownerUserId.equals(ownerUserId))
      ..where((t) => t.deletedAt.isNull())
      ..where(
        (t) => t.status.isIn(<String>[
          ExecutionActionStatus.done.wire,
          ExecutionActionStatus.dropped.wire,
        ]),
      )
      ..orderBy([
        (t) => OrderingTerm(expression: t.completedAt, mode: OrderingMode.desc),
        (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
      ])
      ..limit(limit);
    return q.watch().map((rows) => rows.map(_actionFromRow).toList());
  }

  Stream<List<ExecutionAction>> watchActionsForCommitment({
    required String ownerUserId,
    required String commitmentId,
    int limit = 200,
  }) {
    final q = _db.select(_db.executionActions)
      ..where((t) => t.ownerUserId.equals(ownerUserId))
      ..where((t) => t.deletedAt.isNull())
      ..where((t) => t.commitmentId.equals(commitmentId))
      ..orderBy([
        (t) => OrderingTerm(
          expression: t.status.isIn(<String>[
            ExecutionActionStatus.todo.wire,
            ExecutionActionStatus.doing.wire,
            ExecutionActionStatus.blocked.wire,
          ]),
          mode: OrderingMode.desc,
        ),
        (t) => OrderingTerm(
          expression: t.status.equals(ExecutionActionStatus.blocked.wire),
          mode: OrderingMode.desc,
        ),
        (t) => OrderingTerm(
          expression: t.priority.equals(ExecutionPriority.high.wire),
          mode: OrderingMode.desc,
        ),
        (t) => OrderingTerm(expression: t.completedAt, mode: OrderingMode.desc),
        (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
      ])
      ..limit(limit);
    return q.watch().map((rows) => rows.map(_actionFromRow).toList());
  }

  Future<List<ExecutionAction>> listOpenActions({
    required String ownerUserId,
    int limit = 200,
  }) async {
    final q = _db.select(_db.executionActions)
      ..where((t) => t.ownerUserId.equals(ownerUserId))
      ..where((t) => t.deletedAt.isNull())
      ..where(
        (t) => t.status.isIn(<String>[
          ExecutionActionStatus.todo.wire,
          ExecutionActionStatus.doing.wire,
          ExecutionActionStatus.blocked.wire,
        ]),
      )
      ..orderBy([
        (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
      ])
      ..limit(limit);
    final rows = await q.get();
    return rows.map(_actionFromRow).toList();
  }

  Stream<List<ExecutionAction>> watchActionsForMemoryIndex({
    required String ownerUserId,
    int limit = 500,
  }) {
    final q = _db.select(_db.executionActions)
      ..where((t) => t.ownerUserId.equals(ownerUserId))
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([
        (t) => OrderingTerm(expression: t.updatedAt, mode: OrderingMode.desc),
        (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
      ])
      ..limit(limit);
    return q.watch().map((rows) => rows.map(_actionFromRow).toList());
  }

  Future<ExecutionAction?> findAction({
    required String ownerUserId,
    required String id,
  }) async {
    final row =
        await (_db.select(_db.executionActions)..where(
              (t) => t.id.equals(id) & t.ownerUserId.equals(ownerUserId),
            ))
            .getSingleOrNull();
    return row == null ? null : _actionFromRow(row);
  }

  Stream<ExecutionAction?> watchActionById({
    required String ownerUserId,
    required String id,
  }) {
    final q = _db.select(_db.executionActions)
      ..where((t) => t.id.equals(id) & t.ownerUserId.equals(ownerUserId))
      ..limit(1);
    return q.watchSingleOrNull().map(
      (row) =>
          row == null || row.deletedAt != null ? null : _actionFromRow(row),
    );
  }

  Future<List<ExecutionAction>> listActionsByIds({
    required String ownerUserId,
    required Set<String> ids,
  }) async {
    if (ids.isEmpty) return const <ExecutionAction>[];
    final q = _db.select(_db.executionActions)
      ..where(
        (t) =>
            t.ownerUserId.equals(ownerUserId) &
            t.id.isIn(ids.toList(growable: false)),
      );
    final rows = await q.get();
    return rows.map(_actionFromRow).toList(growable: false);
  }

  Future<void> upsertAction(ExecutionAction action) {
    return _upsertAndEnqueue(
      _db.executionActions,
      _actionCompanion(action),
      tableName: _actionsTable,
      rowId: action.id,
    );
  }

  Future<void> softDeleteAction({
    required ExecutionAction action,
    required SyncMeta sync,
  }) {
    return upsertAction(action.copyWith(sync: _tombstone(sync)));
  }

  Future<void> updateActionStatus({
    required ExecutionAction action,
    required ExecutionActionStatus status,
    required SyncMeta sync,
    String? progressId,
    String? progressNote,
  }) async {
    final updated = _actionWithStatus(action, status: status, sync: sync);
    await _db.transaction(() async {
      await _db
          .into(_db.executionActions)
          .insert(_actionCompanion(updated), mode: InsertMode.insertOrReplace);
      await _outbox.enqueue(table: _actionsTable, rowId: action.id);
      if (progressId != null &&
          progressNote != null &&
          progressNote.trim().isNotEmpty) {
        final progress = ExecutionProgressEntry(
          id: progressId,
          actionId: action.id,
          projectId: action.projectId,
          commitmentId: action.commitmentId,
          kind: switch (status) {
            ExecutionActionStatus.blocked => ExecutionProgressKind.blocker,
            ExecutionActionStatus.done => ExecutionProgressKind.completion,
            ExecutionActionStatus.dropped => ExecutionProgressKind.dropped,
            _ => ExecutionProgressKind.checkin,
          },
          note: progressNote.trim(),
          createdAt: sync.updatedAt,
          sync: sync,
        );
        await _db
            .into(_db.executionProgressEntries)
            .insert(_progressCompanion(progress));
        await _outbox.enqueue(table: _progressTable, rowId: progress.id);
      }
    });
  }

  Future<void> recordProgress(
    ExecutionProgressEntry progress, {
    ExecutionAction? linkedAction,
    ExecutionActionStatus? linkedActionStatus,
  }) async {
    final updatedAction = linkedAction == null || linkedActionStatus == null
        ? null
        : _actionWithStatus(
            linkedAction,
            status: linkedActionStatus,
            sync: progress.sync,
          );
    await _db.transaction(() async {
      await _db
          .into(_db.executionProgressEntries)
          .insert(
            _progressCompanion(progress),
            mode: InsertMode.insertOrReplace,
          );
      await _outbox.enqueue(table: _progressTable, rowId: progress.id);
      if (updatedAction != null) {
        await _db
            .into(_db.executionActions)
            .insert(
              _actionCompanion(updatedAction),
              mode: InsertMode.insertOrReplace,
            );
        await _outbox.enqueue(table: _actionsTable, rowId: updatedAction.id);
      }
    });
  }

  Stream<List<ExecutionCommitment>> watchActiveCommitments({
    required String ownerUserId,
    int limit = 100,
  }) {
    final q = _db.select(_db.executionCommitments)
      ..where((t) => t.ownerUserId.equals(ownerUserId))
      ..where((t) => t.deletedAt.isNull())
      ..where(
        (t) => t.status.isIn(<String>[
          ExecutionCommitmentStatus.active.wire,
          ExecutionCommitmentStatus.paused.wire,
        ]),
      )
      ..orderBy([
        (t) => OrderingTerm(expression: t.targetDate, mode: OrderingMode.asc),
        (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
      ])
      ..limit(limit);
    return q.watch().map((rows) => rows.map(_commitmentFromRow).toList());
  }

  Stream<List<ExecutionCommitment>> watchClosedCommitments({
    required String ownerUserId,
    int limit = 100,
  }) {
    final q = _db.select(_db.executionCommitments)
      ..where((t) => t.ownerUserId.equals(ownerUserId))
      ..where((t) => t.deletedAt.isNull())
      ..where(
        (t) => t.status.isIn(<String>[
          ExecutionCommitmentStatus.completed.wire,
          ExecutionCommitmentStatus.archived.wire,
        ]),
      )
      ..orderBy([
        (t) => OrderingTerm(expression: t.completedAt, mode: OrderingMode.desc),
        (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
      ])
      ..limit(limit);
    return q.watch().map((rows) => rows.map(_commitmentFromRow).toList());
  }

  Future<List<ExecutionCommitment>> listActiveCommitments({
    required String ownerUserId,
    int limit = 100,
  }) async {
    final q = _db.select(_db.executionCommitments)
      ..where((t) => t.ownerUserId.equals(ownerUserId))
      ..where((t) => t.deletedAt.isNull())
      ..where(
        (t) => t.status.isIn(<String>[
          ExecutionCommitmentStatus.active.wire,
          ExecutionCommitmentStatus.paused.wire,
        ]),
      )
      ..orderBy([
        (t) => OrderingTerm(expression: t.targetDate, mode: OrderingMode.asc),
        (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
      ])
      ..limit(limit);
    final rows = await q.get();
    return rows.map(_commitmentFromRow).toList();
  }

  Stream<List<ExecutionCommitment>> watchCommitmentsForMemoryIndex({
    required String ownerUserId,
    int limit = 500,
  }) {
    final q = _db.select(_db.executionCommitments)
      ..where((t) => t.ownerUserId.equals(ownerUserId))
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([
        (t) => OrderingTerm(expression: t.updatedAt, mode: OrderingMode.desc),
        (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
      ])
      ..limit(limit);
    return q.watch().map((rows) => rows.map(_commitmentFromRow).toList());
  }

  Future<void> upsertCommitment(ExecutionCommitment commitment) {
    return _upsertAndEnqueue(
      _db.executionCommitments,
      _commitmentCompanion(commitment),
      tableName: _commitmentsTable,
      rowId: commitment.id,
    );
  }

  Future<void> softDeleteCommitment({
    required ExecutionCommitment commitment,
    required SyncMeta sync,
  }) {
    final tombstone = _tombstone(sync);
    return upsertCommitment(
      ExecutionCommitment(
        id: commitment.id,
        title: commitment.title,
        description: commitment.description,
        status: commitment.status,
        horizon: commitment.horizon,
        targetDate: commitment.targetDate,
        projectId: commitment.projectId,
        source: commitment.source,
        createdAt: commitment.createdAt,
        completedAt: commitment.completedAt,
        sync: tombstone,
      ),
    );
  }

  Future<void> updateCommitmentStatus({
    required ExecutionCommitment commitment,
    required ExecutionCommitmentStatus status,
    required SyncMeta sync,
  }) {
    return upsertCommitment(
      _commitmentWithStatus(commitment, status: status, sync: sync),
    );
  }

  Future<ExecutionCommitment?> findCommitment({
    required String ownerUserId,
    required String id,
  }) async {
    final row =
        await (_db.select(_db.executionCommitments)..where(
              (t) => t.id.equals(id) & t.ownerUserId.equals(ownerUserId),
            ))
            .getSingleOrNull();
    return row == null ? null : _commitmentFromRow(row);
  }

  Stream<ExecutionCommitment?> watchCommitmentById({
    required String ownerUserId,
    required String id,
  }) {
    final q = _db.select(_db.executionCommitments)
      ..where((t) => t.id.equals(id) & t.ownerUserId.equals(ownerUserId))
      ..limit(1);
    return q.watchSingleOrNull().map(
      (row) =>
          row == null || row.deletedAt != null ? null : _commitmentFromRow(row),
    );
  }

  Future<List<ExecutionCommitment>> listCommitmentsByIds({
    required String ownerUserId,
    required Set<String> ids,
  }) async {
    if (ids.isEmpty) return const <ExecutionCommitment>[];
    final q = _db.select(_db.executionCommitments)
      ..where(
        (t) =>
            t.ownerUserId.equals(ownerUserId) &
            t.id.isIn(ids.toList(growable: false)),
      );
    final rows = await q.get();
    return rows.map(_commitmentFromRow).toList(growable: false);
  }

  Stream<List<ExecutionProgressEntry>> watchRecentProgress({
    required String ownerUserId,
    int limit = 100,
  }) {
    final q = _db.select(_db.executionProgressEntries)
      ..where((t) => t.ownerUserId.equals(ownerUserId))
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([
        (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
      ])
      ..limit(limit);
    return q.watch().map((rows) => rows.map(_progressFromRow).toList());
  }

  Stream<List<ExecutionProgressEntry>> watchProgressForAction({
    required String ownerUserId,
    required String actionId,
    int limit = 100,
  }) {
    final q = _db.select(_db.executionProgressEntries)
      ..where((t) => t.ownerUserId.equals(ownerUserId))
      ..where((t) => t.deletedAt.isNull())
      ..where((t) => t.actionId.equals(actionId))
      ..orderBy([
        (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
      ])
      ..limit(limit);
    return q.watch().map((rows) => rows.map(_progressFromRow).toList());
  }

  Stream<List<ExecutionProgressEntry>> watchProgressForCommitment({
    required String ownerUserId,
    required String commitmentId,
    int limit = 100,
  }) {
    final q = _db.select(_db.executionProgressEntries)
      ..where((t) => t.ownerUserId.equals(ownerUserId))
      ..where((t) => t.deletedAt.isNull())
      ..where((t) => t.commitmentId.equals(commitmentId))
      ..orderBy([
        (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
      ])
      ..limit(limit);
    return q.watch().map((rows) => rows.map(_progressFromRow).toList());
  }

  Future<List<ExecutionProgressEntry>> listRecentProgress({
    required String ownerUserId,
    int limit = 100,
  }) async {
    final q = _db.select(_db.executionProgressEntries)
      ..where((t) => t.ownerUserId.equals(ownerUserId))
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([
        (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
      ])
      ..limit(limit);
    final rows = await q.get();
    return rows.map(_progressFromRow).toList();
  }

  Future<void> upsertProgress(ExecutionProgressEntry progress) {
    return _upsertAndEnqueue(
      _db.executionProgressEntries,
      _progressCompanion(progress),
      tableName: _progressTable,
      rowId: progress.id,
    );
  }

  Future<void> softDeleteProgress({
    required ExecutionProgressEntry progress,
    required SyncMeta sync,
  }) {
    final tombstone = _tombstone(sync);
    return upsertProgress(
      ExecutionProgressEntry(
        id: progress.id,
        actionId: progress.actionId,
        projectId: progress.projectId,
        commitmentId: progress.commitmentId,
        kind: progress.kind,
        note: progress.note,
        createdAt: progress.createdAt,
        sync: tombstone,
      ),
    );
  }

  SyncMeta _tombstone(SyncMeta sync) {
    return sync.copyWith(deletedAt: sync.updatedAt);
  }

  ExecutionAction _actionWithStatus(
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

  ExecutionProject _projectWithStatus(
    ExecutionProject project, {
    required ExecutionProjectStatus status,
    required SyncMeta sync,
  }) {
    final completedAt = switch (status) {
      ExecutionProjectStatus.completed ||
      ExecutionProjectStatus.archived => sync.updatedAt,
      ExecutionProjectStatus.active || ExecutionProjectStatus.paused => null,
    };
    return project.copyWith(
      status: status,
      completedAt: completedAt,
      sync: sync,
    );
  }

  ExecutionCommitment _commitmentWithStatus(
    ExecutionCommitment commitment, {
    required ExecutionCommitmentStatus status,
    required SyncMeta sync,
  }) {
    final completedAt = switch (status) {
      ExecutionCommitmentStatus.completed ||
      ExecutionCommitmentStatus.archived => sync.updatedAt,
      ExecutionCommitmentStatus.active ||
      ExecutionCommitmentStatus.paused => null,
    };
    return commitment.copyWith(
      status: status,
      completedAt: completedAt,
      sync: sync,
    );
  }

  Future<ExecutionProgressEntry?> findProgress({
    required String ownerUserId,
    required String id,
  }) async {
    final row =
        await (_db.select(_db.executionProgressEntries)..where(
              (t) => t.id.equals(id) & t.ownerUserId.equals(ownerUserId),
            ))
            .getSingleOrNull();
    return row == null ? null : _progressFromRow(row);
  }

  ExecutionProjectsCompanion _projectCompanion(ExecutionProject project) {
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

  ExecutionActionsCompanion _actionCompanion(ExecutionAction action) {
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

  ExecutionCommitmentsCompanion _commitmentCompanion(
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

  ExecutionProgressEntriesCompanion _progressCompanion(
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

  ExecutionAction _actionFromRow(ExecutionActionRow r) {
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

  ExecutionProject _projectFromRow(ExecutionProjectRow r) {
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

  ExecutionCommitment _commitmentFromRow(ExecutionCommitmentRow r) {
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

  ExecutionProgressEntry _progressFromRow(ExecutionProgressEntryRow r) {
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
}
