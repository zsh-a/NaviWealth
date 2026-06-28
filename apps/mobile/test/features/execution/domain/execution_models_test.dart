import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/execution/domain/execution_models.dart';

const _userId = 'u-exec-models';
const _deviceId = 'dev-exec-models';

void main() {
  test('project and commitment statuses expose open lifecycle semantics', () {
    expect(ExecutionProjectStatus.active.isOpen, isTrue);
    expect(ExecutionProjectStatus.paused.isOpen, isTrue);
    expect(ExecutionProjectStatus.completed.isOpen, isFalse);
    expect(ExecutionProjectStatus.archived.isOpen, isFalse);
    expect(ExecutionCommitmentStatus.active.isOpen, isTrue);
    expect(ExecutionCommitmentStatus.paused.isOpen, isTrue);
    expect(ExecutionCommitmentStatus.completed.isOpen, isFalse);
    expect(ExecutionCommitmentStatus.archived.isOpen, isFalse);
  });

  test('ExecutionAction.copyWith can clear nullable scheduling and links', () {
    final original = ExecutionAction(
      id: 'a1',
      title: 'Review stale execution link',
      dueAt: DateTime.utc(2026, 6, 8),
      scheduledFor: DateTime.utc(2026, 6, 7),
      projectId: 'proj-1',
      commitmentId: 'commit-1',
      completedAt: DateTime.utc(2026, 6, 9),
      createdAt: DateTime.utc(2026, 6, 1),
      sync: _sync(1),
    );

    final cleared = original.copyWith(
      dueAt: null,
      scheduledFor: null,
      projectId: null,
      commitmentId: null,
      completedAt: null,
      sync: _sync(2),
    );

    expect(cleared.dueAt, isNull);
    expect(cleared.scheduledFor, isNull);
    expect(cleared.projectId, isNull);
    expect(cleared.commitmentId, isNull);
    expect(cleared.completedAt, isNull);
  });

  test('ExecutionProject.copyWith can clear target and completion dates', () {
    final original = ExecutionProject(
      id: 'proj-1',
      title: 'Execution project',
      targetDate: DateTime.utc(2026, 7, 1),
      completedAt: DateTime.utc(2026, 7, 2),
      createdAt: DateTime.utc(2026, 6, 1),
      sync: _sync(1),
    );

    final cleared = original.copyWith(
      targetDate: null,
      completedAt: null,
      sync: _sync(2),
    );

    expect(cleared.targetDate, isNull);
    expect(cleared.completedAt, isNull);
  });

  test(
    'ExecutionCommitment.copyWith can clear target project and completion',
    () {
      final original = ExecutionCommitment(
        id: 'commit-1',
        title: 'Execution commitment',
        targetDate: DateTime.utc(2026, 7, 1),
        projectId: 'proj-1',
        completedAt: DateTime.utc(2026, 7, 2),
        createdAt: DateTime.utc(2026, 6, 1),
        sync: _sync(1),
      );

      final cleared = original.copyWith(
        targetDate: null,
        projectId: null,
        completedAt: null,
        sync: _sync(2),
      );

      expect(cleared.targetDate, isNull);
      expect(cleared.projectId, isNull);
      expect(cleared.completedAt, isNull);
    },
  );
}

SyncMeta _sync(int tick) {
  final wall = DateTime.utc(2026, 6, 1, 9, 0, tick);
  return SyncMeta(
    ownerUserId: _userId,
    updatedAt: wall,
    updatedByDevice: _deviceId,
    hlc: Hlc(
      wallMillis: wall.millisecondsSinceEpoch,
      counter: 0,
      nodeId: _deviceId,
    ),
  );
}
