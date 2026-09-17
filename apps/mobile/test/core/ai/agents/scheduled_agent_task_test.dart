import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/agents/agent_schedule.dart';
import 'package:naviwealth/core/ai/agents/scheduled_agent_store.dart';
import 'package:naviwealth/core/ai/agents/scheduled_agent_task.dart';
import 'package:naviwealth/core/auth/domain_scope.dart';

import '../../persistence/test_database.dart';

void main() {
  test('weekly calendar catches up once without shifting next week', () {
    const schedule = AgentSchedule.weekly(weekday: 7, hour: 20, minute: 15);
    final previous = DateTime(2026, 9, 13, 20, 16);
    expect(
      schedule.shouldFire(
        now: DateTime(2026, 9, 20, 20, 14),
        lastRunAt: previous,
      ),
      false,
    );
    expect(
      schedule.shouldFire(
        now: DateTime(2026, 9, 20, 20, 15),
        lastRunAt: previous,
      ),
      true,
    );
    final catchUp = DateTime(2026, 9, 22, 9);
    expect(schedule.shouldFire(now: catchUp, lastRunAt: previous), true);
    expect(
      schedule.nextRunAt(now: catchUp, lastRunAt: catchUp),
      DateTime(2026, 9, 27, 20, 15),
    );
    expect(
      schedule.shouldFire(
        now: DateTime(2026, 9, 27, 20, 15),
        lastRunAt: catchUp,
      ),
      true,
    );
  });

  test(
    'task definitions persist, isolate owners and reject stale updates',
    () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final store = ScheduledAgentStore(db, 'alice');
      final task = ScheduledAgentTask(
        id: 'user_task:1',
        title: 'Weekly report',
        instructions: 'Review my activity',
        domain: DomainScope.health,
        schedule: const AgentSchedule.weekly(weekday: 7, hour: 20),
        createdAt: DateTime(2026, 9, 17),
      );
      await store.save(task, expectedRevision: 0);
      expect(
        (await ScheduledAgentStore(db, 'alice').list()).single.toJson(),
        task.toJson(),
      );
      expect(await ScheduledAgentStore(db, 'bob').list(), isEmpty);
      await expectLater(
        store.save(task, expectedRevision: 0),
        throwsStateError,
      );
      final updated = ScheduledAgentTask.fromJson({
        ...task.toJson(),
        'revision': 2,
        'hour': 19,
      });
      await store.save(updated, expectedRevision: 1);
      await expectLater(
        store.save(updated, expectedRevision: 1),
        throwsStateError,
      );
      await store.save(
        ScheduledAgentTask.fromJson({
          ...updated.toJson(),
          'revision': 3,
          'archived': true,
        }),
        expectedRevision: 2,
      );
      expect((await store.list()).single.archived, true);
    },
  );

  test('invalid schedules and empty objectives fail closed', () {
    final task = ScheduledAgentTask(
      id: 'user_task:1',
      title: 'Report',
      instructions: 'Review',
      domain: DomainScope.finance,
      schedule: const AgentSchedule.weekly(weekday: 1, hour: 9),
      createdAt: DateTime.now(),
    );
    for (final update in <Map<String, Object?>>[
      {'weekday': 0},
      {'weekday': 8},
      {'hour': 24},
      {'minute': 60},
      {'instructions': ''},
      {'domain': 'unknown'},
    ]) {
      expect(
        () => ScheduledAgentTask.fromJson({...task.toJson(), ...update}),
        throwsFormatException,
      );
    }
  });
}
