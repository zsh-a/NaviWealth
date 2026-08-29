import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/execution/domain/execution_models.dart';

const _userId = 'u-exec-models';
const _deviceId = 'dev-exec-models';

void main() {
  test('plan statuses expose open lifecycle semantics', () {
    expect(ExecutionPlanStatus.active.isOpen, isTrue);
    expect(ExecutionPlanStatus.paused.isOpen, isTrue);
    expect(ExecutionPlanStatus.completed.isOpen, isFalse);
    expect(ExecutionPlanStatus.archived.isOpen, isFalse);
  });

  test('ExecutionAction.copyWith can clear nullable scheduling and links', () {
    final original = ExecutionAction(
      id: 'a1',
      title: 'Review stale execution link',
      dueAt: DateTime.utc(2026, 6, 8),
      scheduledFor: DateTime.utc(2026, 6, 7),
      planId: 'plan-1',
      completedAt: DateTime.utc(2026, 6, 9),
      createdAt: DateTime.utc(2026, 6, 1),
      sync: _sync(1),
    );

    final cleared = original.copyWith(
      dueAt: null,
      scheduledFor: null,
      planId: null,
      completedAt: null,
      sync: _sync(2),
    );

    expect(cleared.dueAt, isNull);
    expect(cleared.scheduledFor, isNull);
    expect(cleared.planId, isNull);
    expect(cleared.completedAt, isNull);
  });

  test('ExecutionPlan.copyWith can clear target and completion dates', () {
    final original = ExecutionPlan(
      id: 'plan-1',
      title: 'Execution plan',
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
