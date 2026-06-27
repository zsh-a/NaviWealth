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
  String? projectId,
}) {
  return ExecutionAction(
    id: id,
    title: title,
    status: status,
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
}
