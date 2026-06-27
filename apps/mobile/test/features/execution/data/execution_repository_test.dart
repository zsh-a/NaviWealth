import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/execution/data/execution_repository.dart';
import 'package:naviwealth/features/execution/domain/execution_models.dart';

import '../../../core/persistence/test_database.dart';
import '../../../core/sync/_outbox_test_ext.dart';

const _userId = 'u-exec';
const _deviceId = 'dev-exec';

SyncMeta _sync(int tick, {DateTime? deletedAt}) {
  final wall = DateTime.utc(2026, 6, 1, 8, 0, tick);
  return SyncMeta(
    ownerUserId: _userId,
    updatedAt: wall,
    updatedByDevice: _deviceId,
    hlc: Hlc(
      wallMillis: wall.millisecondsSinceEpoch,
      counter: 0,
      nodeId: _deviceId,
    ),
    deletedAt: deletedAt,
  );
}

ExecutionAction _action({
  required String id,
  required String title,
  ExecutionActionStatus status = ExecutionActionStatus.todo,
  ExecutionPriority priority = ExecutionPriority.normal,
  DateTime? dueAt,
  DateTime? scheduledFor,
  String? projectId,
}) {
  return ExecutionAction(
    id: id,
    title: title,
    status: status,
    priority: priority,
    dueAt: dueAt,
    scheduledFor: scheduledFor,
    projectId: projectId,
    createdAt: DateTime.utc(2026, 6, 1),
    sync: _sync(0),
  );
}

void main() {
  late AppDatabase db;
  late InMemoryOutboxStore outbox;
  late ExecutionRepository repo;

  setUp(() {
    db = makeTestDatabase();
    outbox = InMemoryOutboxStore();
    repo = ExecutionRepository(db: db, outbox: outbox);
  });

  tearDown(() => db.close());

  test('upsertAction stores personal todo and enqueues sync pointer', () async {
    await repo.upsertAction(
      _action(id: 'a1', title: 'Review FIRE budget delta'),
    );

    final rows = await repo.listOpenActions(ownerUserId: _userId);

    expect(rows, hasLength(1));
    expect(rows.single.title, 'Review FIRE budget delta');
    expect(rows.single.status, ExecutionActionStatus.todo);
    expect(outbox.queued, [(table: 'execution_actions', rowId: 'a1')]);
  });

  test('watchTodayActions excludes ordinary unscheduled backlog', () async {
    final now = DateTime.utc(2026, 6, 8, 9);
    await repo.upsertAction(_action(id: 'backlog', title: 'Unscheduled todo'));
    await repo.upsertAction(
      _action(
        id: 'high',
        title: 'High priority follow-up',
        priority: ExecutionPriority.high,
      ),
    );
    await repo.upsertAction(
      _action(
        id: 'scheduled',
        title: 'Scheduled today',
        scheduledFor: DateTime.utc(2026, 6, 8, 12),
      ),
    );
    await repo.upsertAction(
      _action(
        id: 'doing',
        title: 'Already in progress',
        status: ExecutionActionStatus.doing,
      ),
    );

    final rows = await repo
        .watchTodayActions(ownerUserId: _userId, asOf: now)
        .first;
    final ids = rows.map((action) => action.id).toSet();

    expect(ids, containsAll(<String>{'high', 'scheduled', 'doing'}));
    expect(ids, isNot(contains('backlog')));
  });

  test('updateActionStatus can complete action and record progress', () async {
    final action = _action(
      id: 'a1',
      title: 'Book recovery workout',
      projectId: 'proj-1',
    );
    await repo.upsertAction(action);
    outbox.clearQueued();

    await repo.updateActionStatus(
      action: action,
      status: ExecutionActionStatus.done,
      sync: _sync(1),
      progressId: 'p1',
      progressNote: 'Finished after HealthOS review.',
    );

    final open = await repo.listOpenActions(ownerUserId: _userId);
    final progress = await repo.watchRecentProgress(ownerUserId: _userId).first;

    expect(open, isEmpty);
    expect(progress, hasLength(1));
    expect(progress.single.kind, ExecutionProgressKind.completion);
    expect(progress.single.projectId, 'proj-1');
    expect(progress.single.note, 'Finished after HealthOS review.');
    expect(outbox.queued, [
      (table: 'execution_actions', rowId: 'a1'),
      (table: 'execution_progress_entries', rowId: 'p1'),
    ]);
  });

  test('updateActionStatus can drop action and record progress', () async {
    final action = _action(id: 'a-drop', title: 'Drop stale action');
    await repo.upsertAction(action);
    outbox.clearQueued();

    await repo.updateActionStatus(
      action: action,
      status: ExecutionActionStatus.dropped,
      sync: _sync(2),
      progressId: 'p-drop',
      progressNote: 'No longer relevant.',
    );

    final stored = await repo.findAction(ownerUserId: _userId, id: action.id);
    final progress = await repo.watchRecentProgress(ownerUserId: _userId).first;

    expect(stored!.status, ExecutionActionStatus.dropped);
    expect(stored.completedAt, isNotNull);
    expect(progress.single.kind, ExecutionProgressKind.dropped);
    expect(progress.single.note, 'No longer relevant.');
    expect(outbox.queued, [
      (table: 'execution_actions', rowId: 'a-drop'),
      (table: 'execution_progress_entries', rowId: 'p-drop'),
    ]);
  });

  test(
    'updateActionStatus clears completedAt when action is reopened',
    () async {
      final action = _action(id: 'a1', title: 'Reopenable action');
      await repo.upsertAction(action);

      await repo.updateActionStatus(
        action: action,
        status: ExecutionActionStatus.done,
        sync: _sync(1),
      );
      final done = await repo.findAction(ownerUserId: _userId, id: 'a1');
      expect(done!.completedAt, isNotNull);

      await repo.updateActionStatus(
        action: done,
        status: ExecutionActionStatus.doing,
        sync: _sync(2),
      );

      final reopened = await repo.findAction(ownerUserId: _userId, id: 'a1');
      expect(reopened!.status, ExecutionActionStatus.doing);
      expect(reopened.completedAt, isNull);
    },
  );

  test(
    'listActionsByIds resolves completed actions for review history',
    () async {
      final action = _action(id: 'a1', title: 'Close review loop');
      await repo.upsertAction(action);
      await repo.updateActionStatus(
        action: action,
        status: ExecutionActionStatus.done,
        sync: _sync(1),
      );

      final open = await repo.listOpenActions(ownerUserId: _userId);
      final resolved = await repo.listActionsByIds(
        ownerUserId: _userId,
        ids: {'a1'},
      );

      expect(open, isEmpty);
      expect(resolved.single.title, 'Close review loop');
      expect(resolved.single.status, ExecutionActionStatus.done);
    },
  );

  test('watchClosedActions shows done and dropped actions only', () async {
    final open = _action(id: 'a-open', title: 'Open action');
    final done = _action(id: 'a-done', title: 'Done action');
    final dropped = _action(id: 'a-dropped', title: 'Dropped action');
    await repo.upsertAction(open);
    await repo.upsertAction(done);
    await repo.upsertAction(dropped);
    await repo.updateActionStatus(
      action: done,
      status: ExecutionActionStatus.done,
      sync: _sync(1),
    );
    await repo.updateActionStatus(
      action: dropped,
      status: ExecutionActionStatus.dropped,
      sync: _sync(2),
    );
    final closedBeforeDelete = await repo
        .watchClosedActions(ownerUserId: _userId)
        .first;

    expect(
      closedBeforeDelete.map((action) => action.id),
      containsAll(<String>{'a-done', 'a-dropped'}),
    );
    expect(
      closedBeforeDelete.map((action) => action.id),
      isNot(contains('a-open')),
    );

    await repo.softDeleteAction(
      action: closedBeforeDelete.firstWhere((action) => action.id == 'a-done'),
      sync: _sync(3),
    );
    final closedAfterDelete = await repo
        .watchClosedActions(ownerUserId: _userId)
        .first;

    expect(closedAfterDelete.map((action) => action.id), ['a-dropped']);
  });

  test(
    'upsertProject stores active project and enqueues sync pointer',
    () async {
      await repo.upsertProject(
        ExecutionProject(
          id: 'proj-1',
          title: 'Launch execution dashboard',
          description: 'Group actions and progress under one delivery thread.',
          createdAt: DateTime.utc(2026, 6, 1),
          sync: _sync(3),
        ),
      );

      final rows = await repo.watchActiveProjects(ownerUserId: _userId).first;

      expect(rows, hasLength(1));
      expect(rows.single.title, 'Launch execution dashboard');
      expect(rows.single.status, ExecutionProjectStatus.active);
      expect(outbox.queued.last, (
        table: 'execution_projects',
        rowId: 'proj-1',
      ));
    },
  );

  test('updateProjectStatus completes and reopens project lifecycle', () async {
    final project = ExecutionProject(
      id: 'proj-life',
      title: 'Launch execution dashboard',
      createdAt: DateTime.utc(2026, 6, 1),
      sync: _sync(3),
    );
    await repo.upsertProject(project);
    outbox.clearQueued();

    await repo.updateProjectStatus(
      project: project,
      status: ExecutionProjectStatus.completed,
      sync: _sync(4),
    );
    final completed = await repo.findProject(
      ownerUserId: _userId,
      id: project.id,
    );
    final activeAfterComplete = await repo
        .watchActiveProjects(ownerUserId: _userId)
        .first;

    expect(completed!.status, ExecutionProjectStatus.completed);
    expect(completed.completedAt, isNotNull);
    expect(activeAfterComplete, isEmpty);

    await repo.updateProjectStatus(
      project: completed,
      status: ExecutionProjectStatus.active,
      sync: _sync(5),
    );
    final reopened = await repo.findProject(
      ownerUserId: _userId,
      id: project.id,
    );

    expect(reopened!.status, ExecutionProjectStatus.active);
    expect(reopened.completedAt, isNull);
    expect(outbox.queued, [
      (table: 'execution_projects', rowId: 'proj-life'),
      (table: 'execution_projects', rowId: 'proj-life'),
    ]);
  });

  test(
    'watchClosedProjects shows completed and archived projects only',
    () async {
      final active = ExecutionProject(
        id: 'proj-active',
        title: 'Active project',
        createdAt: DateTime.utc(2026, 6, 1),
        sync: _sync(1),
      );
      final completed = ExecutionProject(
        id: 'proj-completed',
        title: 'Completed project',
        createdAt: DateTime.utc(2026, 6, 1),
        sync: _sync(2),
      );
      final archived = ExecutionProject(
        id: 'proj-archived',
        title: 'Archived project',
        createdAt: DateTime.utc(2026, 6, 1),
        sync: _sync(3),
      );
      await repo.upsertProject(active);
      await repo.upsertProject(completed);
      await repo.upsertProject(archived);
      await repo.updateProjectStatus(
        project: completed,
        status: ExecutionProjectStatus.completed,
        sync: _sync(4),
      );
      await repo.updateProjectStatus(
        project: archived,
        status: ExecutionProjectStatus.archived,
        sync: _sync(5),
      );
      final closedBeforeDelete = await repo
          .watchClosedProjects(ownerUserId: _userId)
          .first;

      expect(
        closedBeforeDelete.map((project) => project.id),
        containsAll(<String>{'proj-completed', 'proj-archived'}),
      );
      expect(
        closedBeforeDelete.map((project) => project.id),
        isNot(contains('proj-active')),
      );

      await repo.softDeleteProject(
        project: closedBeforeDelete.firstWhere(
          (project) => project.id == 'proj-archived',
        ),
        sync: _sync(6),
      );
      final closedAfterDelete = await repo
          .watchClosedProjects(ownerUserId: _userId)
          .first;

      expect(closedAfterDelete.map((project) => project.id), [
        'proj-completed',
      ]);
    },
  );

  test('upsertCommitment stores active commitment', () async {
    await repo.upsertCommitment(
      ExecutionCommitment(
        id: 'c1',
        title: 'Ship execution loop',
        description: 'Action, commitment, and review MVP.',
        createdAt: DateTime.utc(2026, 6, 1),
        sync: _sync(2),
      ),
    );

    final rows = await repo.watchActiveCommitments(ownerUserId: _userId).first;

    expect(rows, hasLength(1));
    expect(rows.single.title, 'Ship execution loop');
    expect(outbox.queued.last, (table: 'execution_commitments', rowId: 'c1'));
  });

  test(
    'updateCommitmentStatus pauses completes and reopens commitment lifecycle',
    () async {
      final commitment = ExecutionCommitment(
        id: 'commit-life',
        title: 'Ship execution loop',
        createdAt: DateTime.utc(2026, 6, 1),
        sync: _sync(2),
      );
      await repo.upsertCommitment(commitment);
      outbox.clearQueued();

      await repo.updateCommitmentStatus(
        commitment: commitment,
        status: ExecutionCommitmentStatus.paused,
        sync: _sync(3),
      );
      final paused = await repo.findCommitment(
        ownerUserId: _userId,
        id: commitment.id,
      );
      expect(paused!.status, ExecutionCommitmentStatus.paused);
      expect(paused.completedAt, isNull);

      await repo.updateCommitmentStatus(
        commitment: paused,
        status: ExecutionCommitmentStatus.completed,
        sync: _sync(4),
      );
      final completed = await repo.findCommitment(
        ownerUserId: _userId,
        id: commitment.id,
      );
      final activeAfterComplete = await repo
          .watchActiveCommitments(ownerUserId: _userId)
          .first;

      expect(completed!.status, ExecutionCommitmentStatus.completed);
      expect(completed.completedAt, isNotNull);
      expect(activeAfterComplete, isEmpty);

      await repo.updateCommitmentStatus(
        commitment: completed,
        status: ExecutionCommitmentStatus.active,
        sync: _sync(5),
      );
      final reopened = await repo.findCommitment(
        ownerUserId: _userId,
        id: commitment.id,
      );

      expect(reopened!.status, ExecutionCommitmentStatus.active);
      expect(reopened.completedAt, isNull);
      expect(outbox.queued, [
        (table: 'execution_commitments', rowId: 'commit-life'),
        (table: 'execution_commitments', rowId: 'commit-life'),
        (table: 'execution_commitments', rowId: 'commit-life'),
      ]);
    },
  );

  test(
    'watchClosedCommitments shows completed and archived commitments only',
    () async {
      final active = ExecutionCommitment(
        id: 'commit-active',
        title: 'Active commitment',
        createdAt: DateTime.utc(2026, 6, 1),
        sync: _sync(1),
      );
      final completed = ExecutionCommitment(
        id: 'commit-completed',
        title: 'Completed commitment',
        createdAt: DateTime.utc(2026, 6, 1),
        sync: _sync(2),
      );
      final archived = ExecutionCommitment(
        id: 'commit-archived',
        title: 'Archived commitment',
        createdAt: DateTime.utc(2026, 6, 1),
        sync: _sync(3),
      );
      await repo.upsertCommitment(active);
      await repo.upsertCommitment(completed);
      await repo.upsertCommitment(archived);
      await repo.updateCommitmentStatus(
        commitment: completed,
        status: ExecutionCommitmentStatus.completed,
        sync: _sync(4),
      );
      await repo.updateCommitmentStatus(
        commitment: archived,
        status: ExecutionCommitmentStatus.archived,
        sync: _sync(5),
      );
      final closedBeforeDelete = await repo
          .watchClosedCommitments(ownerUserId: _userId)
          .first;

      expect(
        closedBeforeDelete.map((commitment) => commitment.id),
        containsAll(<String>{'commit-completed', 'commit-archived'}),
      );
      expect(
        closedBeforeDelete.map((commitment) => commitment.id),
        isNot(contains('commit-active')),
      );

      await repo.softDeleteCommitment(
        commitment: closedBeforeDelete.firstWhere(
          (commitment) => commitment.id == 'commit-archived',
        ),
        sync: _sync(6),
      );
      final closedAfterDelete = await repo
          .watchClosedCommitments(ownerUserId: _userId)
          .first;

      expect(closedAfterDelete.map((commitment) => commitment.id), [
        'commit-completed',
      ]);
    },
  );

  test('upsertProgress stores manual review entry and enqueues sync', () async {
    await repo.upsertProgress(
      ExecutionProgressEntry(
        id: 'p-review',
        projectId: 'proj-1',
        commitmentId: 'c1',
        kind: ExecutionProgressKind.checkin,
        note: 'Weekly review captured manually.',
        createdAt: DateTime.utc(2026, 6, 2),
        sync: _sync(4),
      ),
    );

    final rows = await repo.listRecentProgress(ownerUserId: _userId);

    expect(rows, hasLength(1));
    expect(rows.single.kind, ExecutionProgressKind.checkin);
    expect(rows.single.projectId, 'proj-1');
    expect(rows.single.commitmentId, 'c1');
    expect(outbox.queued.last, (
      table: 'execution_progress_entries',
      rowId: 'p-review',
    ));
  });

  test('recordProgress can update linked action status atomically', () async {
    final action = _action(id: 'a1', title: 'Finish execution review');
    await repo.upsertAction(action);
    outbox.clearQueued();

    await repo.recordProgress(
      ExecutionProgressEntry(
        id: 'p-done',
        actionId: action.id,
        kind: ExecutionProgressKind.completion,
        note: 'Review finished.',
        createdAt: DateTime.utc(2026, 6, 2),
        sync: _sync(5),
      ),
      linkedAction: action,
      linkedActionStatus: ExecutionActionStatus.done,
    );

    final stored = await repo.findAction(ownerUserId: _userId, id: action.id);
    final progress = await repo.listRecentProgress(ownerUserId: _userId);

    expect(stored!.status, ExecutionActionStatus.done);
    expect(stored.completedAt, isNotNull);
    expect(progress.single.note, 'Review finished.');
    expect(outbox.queued, [
      (table: 'execution_progress_entries', rowId: 'p-done'),
      (table: 'execution_actions', rowId: 'a1'),
    ]);
  });

  test(
    'softDeleteAction tombstones action and hides it from open lists',
    () async {
      final action = _action(id: 'a-delete', title: 'Remove stale todo');
      await repo.upsertAction(action);
      outbox.clearQueued();

      await repo.softDeleteAction(action: action, sync: _sync(6));

      final open = await repo.listOpenActions(ownerUserId: _userId);
      final tombstoned = await repo.findAction(
        ownerUserId: _userId,
        id: action.id,
      );
      final resolved = await repo.listActionsByIds(
        ownerUserId: _userId,
        ids: {action.id},
      );

      expect(open, isEmpty);
      expect(tombstoned!.sync.deletedAt, isNotNull);
      expect(resolved.single.title, 'Remove stale todo');
      expect(outbox.queued, [(table: 'execution_actions', rowId: 'a-delete')]);
    },
  );

  test(
    'softDeleteProject tombstones project and hides it from active lists',
    () async {
      final project = ExecutionProject(
        id: 'proj-delete',
        title: 'Stale project',
        createdAt: DateTime.utc(2026, 6, 1),
        sync: _sync(7),
      );
      await repo.upsertProject(project);
      outbox.clearQueued();

      await repo.softDeleteProject(project: project, sync: _sync(8));

      final active = await repo.watchActiveProjects(ownerUserId: _userId).first;
      final tombstoned = await repo.findProject(
        ownerUserId: _userId,
        id: project.id,
      );
      final resolved = await repo.listProjectsByIds(
        ownerUserId: _userId,
        ids: {project.id},
      );

      expect(active, isEmpty);
      expect(tombstoned!.sync.deletedAt, isNotNull);
      expect(resolved.single.title, 'Stale project');
      expect(outbox.queued, [
        (table: 'execution_projects', rowId: 'proj-delete'),
      ]);
    },
  );

  test(
    'softDeleteCommitment tombstones commitment and hides it from active lists',
    () async {
      final commitment = ExecutionCommitment(
        id: 'commit-delete',
        title: 'Stale commitment',
        createdAt: DateTime.utc(2026, 6, 1),
        sync: _sync(9),
      );
      await repo.upsertCommitment(commitment);
      outbox.clearQueued();

      await repo.softDeleteCommitment(commitment: commitment, sync: _sync(10));

      final active = await repo
          .watchActiveCommitments(ownerUserId: _userId)
          .first;
      final tombstoned = await repo.findCommitment(
        ownerUserId: _userId,
        id: commitment.id,
      );
      final resolved = await repo.listCommitmentsByIds(
        ownerUserId: _userId,
        ids: {commitment.id},
      );

      expect(active, isEmpty);
      expect(tombstoned!.sync.deletedAt, isNotNull);
      expect(resolved.single.title, 'Stale commitment');
      expect(outbox.queued, [
        (table: 'execution_commitments', rowId: 'commit-delete'),
      ]);
    },
  );

  test(
    'softDeleteProgress tombstones progress and hides it from review',
    () async {
      final progress = ExecutionProgressEntry(
        id: 'progress-delete',
        kind: ExecutionProgressKind.checkin,
        note: 'Stale progress',
        createdAt: DateTime.utc(2026, 6, 2),
        sync: _sync(11),
      );
      await repo.upsertProgress(progress);
      outbox.clearQueued();

      await repo.softDeleteProgress(progress: progress, sync: _sync(12));

      final recent = await repo.listRecentProgress(ownerUserId: _userId);
      final tombstoned = await repo.findProgress(
        ownerUserId: _userId,
        id: progress.id,
      );

      expect(recent, isEmpty);
      expect(tombstoned!.sync.deletedAt, isNotNull);
      expect(outbox.queued, [
        (table: 'execution_progress_entries', rowId: 'progress-delete'),
      ]);
    },
  );
}
