import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/agents/agent.dart';
import 'package:naviwealth/core/ai/agents/agent_run_store.dart';
import 'package:naviwealth/core/ai/agents/agent_schedule.dart';

import '../../../core/persistence/test_database.dart';

void main() {
  test('sqlite store maps run results to lifecycle rows', () async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final store = SqliteAgentRunStore(db: db);
    const agent = _RunStoreAgent();
    final completedAt = DateTime.utc(2026, 7, 5, 8);
    final skippedAt = DateTime.utc(2026, 7, 5, 9);
    final failedAt = DateTime.utc(2026, 7, 5, 10);
    final completedFinishedAt = completedAt.add(
      const Duration(milliseconds: 10),
    );
    final skippedFinishedAt = skippedAt.add(const Duration(milliseconds: 10));

    await _record(
      store,
      agent: agent,
      startedAt: completedAt,
      result: AgentRunResult(
        agentId: agent.id,
        status: AgentRunStatus.completed,
        startedAt: completedAt,
        finishedAt: completedFinishedAt,
        summary: 'ready result',
        memoryId: 'memory-ready',
        artifactId: 'artifact-ready',
        traceId: 'trace-ready',
      ),
      trigger: AgentRunTrigger.schedule,
    );
    await _record(
      store,
      agent: agent,
      startedAt: skippedAt,
      result: AgentRunResult.skipped(
        agentId: agent.id,
        startedAt: skippedAt,
        finishedAt: skippedFinishedAt,
        reason: 'nothing new',
        traceId: 'trace-skipped',
      ),
      trigger: AgentRunTrigger.catchUp,
    );
    await _record(
      store,
      agent: agent,
      startedAt: failedAt,
      result: AgentRunResult.failed(
        agentId: agent.id,
        startedAt: failedAt,
        finishedAt: failedAt.add(const Duration(milliseconds: 10)),
        error: 'runtime failed',
        traceId: 'trace-failed',
      ),
      trigger: AgentRunTrigger.manual,
    );

    final history = await store.listForAgent(
      ownerUserId: 'user-1',
      agentId: agent.id,
    );
    expect(history.map((run) => run.status), <AgentRunLifecycleStatus>[
      AgentRunLifecycleStatus.failed,
      AgentRunLifecycleStatus.noFinding,
      AgentRunLifecycleStatus.ready,
    ]);
    expect(history.first.error, 'runtime failed');
    expect(history[1].summary, 'nothing new');
    expect(history[2].artifactId, 'artifact-ready');
    expect(history[2].traceId, 'trace-ready');
    expect(
      await store.lastNonFailedRunAt(ownerUserId: 'user-1', agentId: agent.id),
      skippedFinishedAt,
    );
  });

  test('lastNonFailedRunAt uses completion time for schedule gates', () async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final store = SqliteAgentRunStore(db: db);
    const agent = _RunStoreAgent();
    final shortRunStartedAt = DateTime.utc(2026, 7, 5, 8);
    final longRunStartedAt = DateTime.utc(2026, 7, 5, 7);
    final longRunFinishedAt = DateTime.utc(2026, 7, 5, 9);

    await _record(
      store,
      agent: agent,
      startedAt: shortRunStartedAt,
      result: AgentRunResult(
        agentId: agent.id,
        status: AgentRunStatus.completed,
        startedAt: shortRunStartedAt,
        finishedAt: shortRunStartedAt.add(const Duration(minutes: 1)),
      ),
      trigger: AgentRunTrigger.schedule,
    );
    await _record(
      store,
      agent: agent,
      startedAt: longRunStartedAt,
      result: AgentRunResult(
        agentId: agent.id,
        status: AgentRunStatus.completed,
        startedAt: longRunStartedAt,
        finishedAt: longRunFinishedAt,
      ),
      trigger: AgentRunTrigger.schedule,
    );

    expect(
      await store.lastNonFailedRunAt(ownerUserId: 'user-1', agentId: agent.id),
      longRunFinishedAt,
    );
  });

  test('lastAutomaticRunAt ignores successful manual runs', () async {
    const agent = _RunStoreAgent();
    final automaticStartedAt = DateTime.utc(2026, 7, 5, 8);
    final automaticFinishedAt = automaticStartedAt.add(
      const Duration(minutes: 1),
    );
    final manualStartedAt = automaticStartedAt.add(const Duration(hours: 1));
    final manualFinishedAt = manualStartedAt.add(const Duration(minutes: 1));

    final inMemory = InMemoryAgentRunStore();
    await _record(
      inMemory,
      agent: agent,
      startedAt: automaticStartedAt,
      result: AgentRunResult(
        agentId: agent.id,
        status: AgentRunStatus.completed,
        startedAt: automaticStartedAt,
        finishedAt: automaticFinishedAt,
      ),
      trigger: AgentRunTrigger.schedule,
    );
    await _record(
      inMemory,
      agent: agent,
      startedAt: manualStartedAt,
      result: AgentRunResult(
        agentId: agent.id,
        status: AgentRunStatus.completed,
        startedAt: manualStartedAt,
        finishedAt: manualFinishedAt,
      ),
      trigger: AgentRunTrigger.manual,
    );
    expect(
      await inMemory.lastNonFailedRunAt(
        ownerUserId: 'user-1',
        agentId: agent.id,
      ),
      manualFinishedAt,
    );
    expect(
      await inMemory.lastAutomaticRunAt(
        ownerUserId: 'user-1',
        agentId: agent.id,
      ),
      automaticFinishedAt,
    );

    final db = makeTestDatabase();
    addTearDown(db.close);
    final sqlite = SqliteAgentRunStore(db: db);
    await _record(
      sqlite,
      agent: agent,
      startedAt: automaticStartedAt,
      result: AgentRunResult(
        agentId: agent.id,
        status: AgentRunStatus.completed,
        startedAt: automaticStartedAt,
        finishedAt: automaticFinishedAt,
      ),
      trigger: AgentRunTrigger.schedule,
    );
    await _record(
      sqlite,
      agent: agent,
      startedAt: manualStartedAt,
      result: AgentRunResult(
        agentId: agent.id,
        status: AgentRunStatus.completed,
        startedAt: manualStartedAt,
        finishedAt: manualFinishedAt,
      ),
      trigger: AgentRunTrigger.manual,
    );
    expect(
      await sqlite.lastAutomaticRunAt(ownerUserId: 'user-1', agentId: agent.id),
      automaticFinishedAt,
    );
  });

  test(
    'in-memory lastNonFailedRunAt matches sqlite completion semantics',
    () async {
      final store = InMemoryAgentRunStore();
      const agent = _RunStoreAgent();
      final shortRunStartedAt = DateTime.utc(2026, 7, 5, 8);
      final longRunStartedAt = DateTime.utc(2026, 7, 5, 7);
      final longRunFinishedAt = DateTime.utc(2026, 7, 5, 9);

      await _record(
        store,
        agent: agent,
        startedAt: shortRunStartedAt,
        result: AgentRunResult(
          agentId: agent.id,
          status: AgentRunStatus.completed,
          startedAt: shortRunStartedAt,
          finishedAt: shortRunStartedAt.add(const Duration(minutes: 1)),
        ),
        trigger: AgentRunTrigger.schedule,
      );
      await _record(
        store,
        agent: agent,
        startedAt: longRunStartedAt,
        result: AgentRunResult(
          agentId: agent.id,
          status: AgentRunStatus.completed,
          startedAt: longRunStartedAt,
          finishedAt: longRunFinishedAt,
        ),
        trigger: AgentRunTrigger.schedule,
      );

      expect(
        await store.lastNonFailedRunAt(
          ownerUserId: 'user-1',
          agentId: agent.id,
        ),
        longRunFinishedAt,
      );
    },
  );

  test('markRunning persists an in-flight lifecycle row', () async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final store = SqliteAgentRunStore(db: db);
    const agent = _RunStoreAgent();
    final startedAt = DateTime.utc(2026, 7, 5, 8);

    await store.markRunning(
      ownerUserId: 'user-1',
      agent: agent,
      startedAt: startedAt,
      trigger: AgentRunTrigger.backgroundDue,
    );

    final latest = await store.latestForAgent(
      ownerUserId: 'user-1',
      agentId: agent.id,
    );
    expect(latest?.status, AgentRunLifecycleStatus.running);
    expect(latest?.trigger, AgentRunTrigger.backgroundDue);
    expect(latest?.startedAt, startedAt);
    expect(latest?.finishedAt, isNull);
    expect(latest?.summary, isNull);
  });

  test('sqlite acquire allows only one fresh running lease', () async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final store = SqliteAgentRunStore(db: db);
    const agent = _RunStoreAgent();
    final startedAt = DateTime.utc(2026, 7, 5, 8);

    final results = await Future.wait([
      store.acquireRun(
        ownerUserId: 'user-1',
        agent: agent,
        startedAt: startedAt,
        trigger: AgentRunTrigger.schedule,
      ),
      store.acquireRun(
        ownerUserId: 'user-1',
        agent: agent,
        startedAt: startedAt.add(const Duration(milliseconds: 1)),
        trigger: AgentRunTrigger.manual,
      ),
    ]);

    expect(results.where((result) => result.acquired), hasLength(1));
    expect(results.where((result) => !result.acquired), hasLength(1));

    final history = await store.listForAgent(
      ownerUserId: 'user-1',
      agentId: agent.id,
    );
    expect(history, hasLength(1));
    expect(history.single.status, AgentRunLifecycleStatus.running);
  });

  test('sqlite acquire abandons stale running rows before new lease', () async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final store = SqliteAgentRunStore(db: db);
    const agent = _RunStoreAgent();
    final staleStartedAt = DateTime.utc(2026, 7, 5, 8);
    final newStartedAt = staleStartedAt
        .add(kAgentRunLeaseTimeout)
        .add(const Duration(minutes: 1));

    final first = await store.acquireRun(
      ownerUserId: 'user-1',
      agent: agent,
      startedAt: staleStartedAt,
      trigger: AgentRunTrigger.schedule,
    );
    final second = await store.acquireRun(
      ownerUserId: 'user-1',
      agent: agent,
      startedAt: newStartedAt,
      trigger: AgentRunTrigger.manual,
    );

    expect(first.acquired, isTrue);
    expect(second.acquired, isTrue);

    await store.finishRun(
      ownerUserId: 'user-1',
      agent: agent,
      runStartedAt: staleStartedAt,
      result: AgentRunResult(
        agentId: agent.id,
        status: AgentRunStatus.completed,
        startedAt: staleStartedAt,
        finishedAt: staleStartedAt.add(const Duration(minutes: 1)),
        summary: 'late finish should not resurrect',
      ),
      trigger: AgentRunTrigger.schedule,
    );

    final history = await store.listForAgent(
      ownerUserId: 'user-1',
      agentId: agent.id,
    );

    expect(history.map((run) => run.status), <AgentRunLifecycleStatus>[
      AgentRunLifecycleStatus.running,
      AgentRunLifecycleStatus.failed,
    ]);
    expect(history.first.startedAt, newStartedAt);
    expect(history.last.error, contains('stale running lease'));
    expect(
      await store.lastNonFailedRunAt(ownerUserId: 'user-1', agentId: agent.id),
      isNull,
    );
  });
}

Future<void> _record(
  AgentRunStore store, {
  required _RunStoreAgent agent,
  required DateTime startedAt,
  required AgentRunResult result,
  required AgentRunTrigger trigger,
}) async {
  await store.markRunning(
    ownerUserId: 'user-1',
    agent: agent,
    startedAt: startedAt,
    trigger: trigger,
  );
  await store.finishRun(
    ownerUserId: 'user-1',
    agent: agent,
    runStartedAt: startedAt,
    result: result,
    trigger: trigger,
  );
}

class _RunStoreAgent implements Agent {
  const _RunStoreAgent();

  @override
  String get id => 'run-store-agent';

  @override
  String get name => 'Run Store Agent';

  @override
  AgentSchedule get schedule =>
      const AgentSchedule(interval: Duration(days: 1));

  @override
  Future<AgentRunResult> run(AgentContext ctx) async {
    return AgentRunResult.skipped(
      agentId: id,
      startedAt: ctx.now,
      finishedAt: ctx.now,
      reason: 'not used',
    );
  }
}
