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

    await _record(
      store,
      agent: agent,
      startedAt: completedAt,
      result: AgentRunResult(
        agentId: agent.id,
        status: AgentRunStatus.completed,
        startedAt: completedAt,
        finishedAt: completedAt.add(const Duration(milliseconds: 10)),
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
        finishedAt: skippedAt.add(const Duration(milliseconds: 10)),
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
      skippedAt,
    );
  });

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
