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
  String? planId,
}) {
  return ExecutionAction(
    id: id,
    title: title,
    status: status,
    priority: priority,
    dueAt: dueAt,
    scheduledFor: scheduledFor,
    planId: planId,
    createdAt: DateTime.utc(2026, 6, 1),
    sync: _sync(0),
  );
}

ExecutionProgressEntry _progress({
  required String id,
  required SyncMeta sync,
  String? planId,
}) {
  return ExecutionProgressEntry(
    id: id,
    planId: planId,
    kind: ExecutionProgressKind.checkin,
    note: 'Lifecycle changed',
    createdAt: sync.updatedAt,
    sync: sync,
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

  test(
    'watchTodayActions only promotes scheduled or active follow-through',
    () async {
      final now = DateTime.utc(2026, 6, 8, 9);
      await repo.upsertAction(
        _action(id: 'backlog', title: 'Unscheduled todo'),
      );
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

      expect(ids, containsAll(<String>{'scheduled', 'doing'}));
      expect(ids, isNot(contains('high')));
      expect(ids, isNot(contains('backlog')));
    },
  );

  test('updateActionStatus can complete action and record progress', () async {
    final action = _action(
      id: 'a1',
      title: 'Book recovery workout',
      planId: 'proj-1',
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
    expect(progress.single.planId, 'proj-1');
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

  test('upsertPlan stores active plan and enqueues sync pointer', () async {
    await repo.upsertPlan(
      ExecutionPlan(
        id: 'proj-1',
        title: 'Launch execution dashboard',
        description: 'Group actions and progress under one delivery thread.',
        createdAt: DateTime.utc(2026, 6, 1),
        sync: _sync(3),
      ),
    );

    final rows = await repo.watchActivePlans(ownerUserId: _userId).first;

    expect(rows, hasLength(1));
    expect(rows.single.title, 'Launch execution dashboard');
    expect(rows.single.status, ExecutionPlanStatus.active);
    expect(outbox.queued.last, (table: 'execution_plans', rowId: 'proj-1'));
  });

  test('updatePlanStatus completes and reopens plan lifecycle', () async {
    final plan = ExecutionPlan(
      id: 'proj-life',
      title: 'Launch execution dashboard',
      createdAt: DateTime.utc(2026, 6, 1),
      sync: _sync(3),
    );
    await repo.upsertPlan(plan);
    outbox.clearQueued();

    await repo.updatePlanStatus(
      plan: plan,
      status: ExecutionPlanStatus.completed,
      sync: _sync(4),
      progress: _progress(
        id: 'progress-plan-complete',
        planId: plan.id,
        sync: _sync(4),
      ),
    );
    final completed = await repo.findPlan(ownerUserId: _userId, id: plan.id);
    final activeAfterComplete = await repo
        .watchActivePlans(ownerUserId: _userId)
        .first;

    expect(completed!.status, ExecutionPlanStatus.completed);
    expect(completed.completedAt, isNotNull);
    expect(activeAfterComplete, isEmpty);

    await repo.updatePlanStatus(
      plan: completed,
      status: ExecutionPlanStatus.active,
      sync: _sync(5),
      progress: _progress(
        id: 'progress-plan-reopen',
        planId: plan.id,
        sync: _sync(5),
      ),
    );
    final reopened = await repo.findPlan(ownerUserId: _userId, id: plan.id);

    expect(reopened!.status, ExecutionPlanStatus.active);
    expect(reopened.completedAt, isNull);
    expect(outbox.queued, [
      (table: 'execution_plans', rowId: 'proj-life'),
      (table: 'execution_progress_entries', rowId: 'progress-plan-complete'),
      (table: 'execution_plans', rowId: 'proj-life'),
      (table: 'execution_progress_entries', rowId: 'progress-plan-reopen'),
    ]);
  });

  test('closing a plan moves open actions to Inbox', () async {
    final plan = ExecutionPlan(
      id: 'proj-inbox',
      title: 'Plan with follow-through',
      createdAt: DateTime.utc(2026, 6, 1),
      sync: _sync(20),
    );
    final action = _action(
      id: 'action-inbox',
      title: 'Keep the follow-through visible',
      planId: plan.id,
    );
    await repo.upsertPlan(plan);
    await repo.upsertAction(action);
    outbox.clearQueued();

    final progress = _progress(
      id: 'progress-plan-inbox',
      planId: plan.id,
      sync: _sync(21),
    );
    final moved = await repo.updatePlanStatus(
      plan: plan,
      status: ExecutionPlanStatus.completed,
      sync: _sync(21),
      progress: progress,
    );

    expect(moved.map((item) => item.id), ['action-inbox']);
    final stored = await repo.findAction(ownerUserId: _userId, id: action.id);
    expect(stored!.status, ExecutionActionStatus.todo);
    expect(stored.planId, isNull);
    expect(
      (await repo.listOpenActions(ownerUserId: _userId)).map((item) => item.id),
      contains('action-inbox'),
    );
    expect(
      outbox.queued,
      contains((table: 'execution_actions', rowId: 'action-inbox')),
    );
  });

  test('watchClosedPlans shows completed and archived plans only', () async {
    final active = ExecutionPlan(
      id: 'proj-active',
      title: 'Active plan',
      createdAt: DateTime.utc(2026, 6, 1),
      sync: _sync(1),
    );
    final completed = ExecutionPlan(
      id: 'proj-completed',
      title: 'Completed plan',
      createdAt: DateTime.utc(2026, 6, 1),
      sync: _sync(2),
    );
    final archived = ExecutionPlan(
      id: 'proj-archived',
      title: 'Archived plan',
      createdAt: DateTime.utc(2026, 6, 1),
      sync: _sync(3),
    );
    await repo.upsertPlan(active);
    await repo.upsertPlan(completed);
    await repo.upsertPlan(archived);
    await repo.updatePlanStatus(
      plan: completed,
      status: ExecutionPlanStatus.completed,
      sync: _sync(4),
      progress: _progress(
        id: 'progress-plan-closed',
        planId: completed.id,
        sync: _sync(4),
      ),
    );
    await repo.updatePlanStatus(
      plan: archived,
      status: ExecutionPlanStatus.archived,
      sync: _sync(5),
      progress: _progress(
        id: 'progress-plan-archived',
        planId: archived.id,
        sync: _sync(5),
      ),
    );
    final closedBeforeDelete = await repo
        .watchClosedPlans(ownerUserId: _userId)
        .first;

    expect(
      closedBeforeDelete.map((plan) => plan.id),
      containsAll(<String>{'proj-completed', 'proj-archived'}),
    );
    expect(
      closedBeforeDelete.map((plan) => plan.id),
      isNot(contains('proj-active')),
    );

    await repo.softDeletePlan(
      plan: closedBeforeDelete.firstWhere((plan) => plan.id == 'proj-archived'),
      sync: _sync(6),
    );
    final closedAfterDelete = await repo
        .watchClosedPlans(ownerUserId: _userId)
        .first;

    expect(closedAfterDelete.map((plan) => plan.id), ['proj-completed']);
  });

  test('upsertProgress stores manual review entry and enqueues sync', () async {
    await repo.upsertProgress(
      ExecutionProgressEntry(
        id: 'p-review',
        planId: 'plan-1',
        kind: ExecutionProgressKind.checkin,
        note: 'Weekly review captured manually.',
        createdAt: DateTime.utc(2026, 6, 2),
        sync: _sync(4),
      ),
    );

    final rows = await repo.listRecentProgress(ownerUserId: _userId);

    expect(rows, hasLength(1));
    expect(rows.single.kind, ExecutionProgressKind.checkin);
    expect(rows.single.planId, 'plan-1');
    expect(outbox.queued.last, (
      table: 'execution_progress_entries',
      rowId: 'p-review',
    ));
  });

  test('detail watchers resolve plan-scoped data', () async {
    await repo.upsertPlan(
      ExecutionPlan(
        id: 'plan-detail',
        title: 'Plan detail',
        createdAt: DateTime.utc(2026, 6, 1),
        sync: _sync(1),
      ),
    );
    final linked = _action(
      id: 'a-linked',
      title: 'Open linked action',
      planId: 'plan-detail',
    );
    final other = _action(id: 'a-other', title: 'Unrelated action');
    await repo.upsertAction(linked);
    await repo.upsertAction(other);
    await repo.upsertProgress(
      ExecutionProgressEntry(
        id: 'p-linked',
        actionId: linked.id,
        planId: 'plan-detail',
        kind: ExecutionProgressKind.checkin,
        note: 'Detail progress',
        createdAt: DateTime.utc(2026, 6, 2),
        sync: _sync(3),
      ),
    );
    await repo.upsertProgress(
      ExecutionProgressEntry(
        id: 'p-other',
        actionId: other.id,
        kind: ExecutionProgressKind.checkin,
        note: 'Other progress',
        createdAt: DateTime.utc(2026, 6, 2),
        sync: _sync(4),
      ),
    );

    final plan = await repo
        .watchPlanById(ownerUserId: _userId, id: 'plan-detail')
        .first;
    final planActions = await repo
        .watchActionsForPlan(ownerUserId: _userId, planId: 'plan-detail')
        .first;
    final actionProgress = await repo
        .watchProgressForAction(ownerUserId: _userId, actionId: linked.id)
        .first;
    final planProgress = await repo
        .watchProgressForPlan(ownerUserId: _userId, planId: 'plan-detail')
        .first;

    expect(plan?.id, 'plan-detail');
    expect(planActions.map((action) => action.id), ['a-linked']);
    expect(actionProgress.map((entry) => entry.id), ['p-linked']);
    expect(planProgress.map((entry) => entry.id), ['p-linked']);
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
    'softDeletePlan tombstones plan and hides it from active lists',
    () async {
      final plan = ExecutionPlan(
        id: 'proj-delete',
        title: 'Stale plan',
        createdAt: DateTime.utc(2026, 6, 1),
        sync: _sync(7),
      );
      await repo.upsertPlan(plan);
      outbox.clearQueued();

      await repo.softDeletePlan(plan: plan, sync: _sync(8));

      final active = await repo.watchActivePlans(ownerUserId: _userId).first;
      final tombstoned = await repo.findPlan(ownerUserId: _userId, id: plan.id);
      final resolved = await repo.listPlansByIds(
        ownerUserId: _userId,
        ids: {plan.id},
      );

      expect(active, isEmpty);
      expect(tombstoned!.sync.deletedAt, isNotNull);
      expect(resolved.single.title, 'Stale plan');
      expect(outbox.queued, [(table: 'execution_plans', rowId: 'proj-delete')]);
    },
  );

  test('softDeletePlan moves open actions to Inbox', () async {
    final plan = ExecutionPlan(
      id: 'proj-delete-inbox',
      title: 'Plan to delete',
      createdAt: DateTime.utc(2026, 6, 1),
      sync: _sync(24),
    );
    final action = _action(
      id: 'action-delete-inbox',
      title: 'Preserve deleted plan follow-through',
      planId: plan.id,
    );
    await repo.upsertPlan(plan);
    await repo.upsertAction(action);

    final moved = await repo.softDeletePlan(plan: plan, sync: _sync(25));

    expect(moved.map((item) => item.id), ['action-delete-inbox']);
    final stored = await repo.findAction(ownerUserId: _userId, id: action.id);
    expect(stored!.planId, isNull);
  });

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

  test('search covers closed actions and plan descriptions', () async {
    await repo.upsertAction(
      ExecutionAction(
        id: 'closed-search',
        title: 'Ship allocation review',
        note: 'Contains 100% and underscore_value literally',
        status: ExecutionActionStatus.done,
        completedAt: DateTime.utc(2026, 6, 2),
        createdAt: DateTime.utc(2026, 6, 1),
        sync: _sync(20),
      ),
    );
    await repo.upsertPlan(
      ExecutionPlan(
        id: 'plan-search',
        title: 'Portfolio cleanup',
        description: 'Consolidate brokerage accounts',
        createdAt: DateTime.utc(2026, 6, 1),
        sync: _sync(21),
      ),
    );
    await repo.upsertAction(
      ExecutionAction(
        id: 'other-owner',
        title: 'Consolidate brokerage accounts privately',
        createdAt: DateTime.utc(2026, 6, 1),
        sync: SyncMeta(
          ownerUserId: 'another-owner',
          updatedAt: DateTime.utc(2026, 6, 1),
          updatedByDevice: _deviceId,
          hlc: Hlc.zero(_deviceId),
        ),
      ),
    );

    final planHits = await repo.search(
      ownerUserId: _userId,
      query: 'brokerage',
    );
    final percentHits = await repo.search(ownerUserId: _userId, query: '%');
    final underscoreHits = await repo.search(ownerUserId: _userId, query: '_');

    expect(planHits.map((hit) => hit.id), ['plan-search']);
    expect(planHits.single.kind, ExecutionEntryKind.plan);
    expect(percentHits.map((hit) => hit.id), ['closed-search']);
    expect(underscoreHits.map((hit) => hit.id), ['closed-search']);
    expect(percentHits.single.status, ExecutionActionStatus.done.wire);
  });
}
