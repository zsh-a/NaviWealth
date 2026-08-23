import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/agents/agent.dart';
import 'package:naviwealth/core/ai/agents/agent_preference_store.dart';
import 'package:naviwealth/core/ai/agents/agent_run_controller.dart';
import 'package:naviwealth/core/ai/agents/agent_run_store.dart';
import 'package:naviwealth/core/ai/agents/agent_runner.dart';
import 'package:naviwealth/core/ai/agents/agent_schedule.dart';
import 'package:naviwealth/core/ai/local/embedding/embedder.dart';
import 'package:naviwealth/core/ai/local/memory/event_store.dart';
import 'package:naviwealth/core/ai/local/memory/memory_runtime.dart';
import 'package:naviwealth/core/ai/local/memory/memory_store.dart';
import 'package:naviwealth/core/persistence/app_database.dart';

import '../../../core/persistence/test_database.dart';

class _StubAgent implements Agent {
  _StubAgent({
    required this.id,
    AgentSchedule? schedule,
    AgentRunResult Function(AgentContext)? onRun,
    Object? throws,
  }) : schedule = schedule ?? const AgentSchedule(interval: Duration(hours: 1)),
       _onRun = onRun,
       _throws = throws;

  @override
  final String id;

  @override
  String get name => id;

  @override
  final AgentSchedule schedule;

  final AgentRunResult Function(AgentContext)? _onRun;
  final Object? _throws;

  int runCount = 0;

  @override
  Future<AgentRunResult> run(AgentContext ctx) async {
    runCount += 1;
    if (_throws != null) throw _throws;
    if (_onRun != null) return _onRun(ctx);
    return AgentRunResult(
      agentId: id,
      status: AgentRunStatus.completed,
      startedAt: ctx.now,
      finishedAt: ctx.now.add(const Duration(milliseconds: 10)),
      summary: 'ok',
    );
  }
}

class _BlockingAgent implements Agent {
  _BlockingAgent({required this.id});

  @override
  final String id;

  @override
  String get name => id;

  @override
  AgentSchedule get schedule =>
      const AgentSchedule(interval: Duration(hours: 1));

  final Completer<void> started = Completer<void>();
  final Completer<AgentRunResult> _result = Completer<AgentRunResult>();
  int runCount = 0;

  @override
  Future<AgentRunResult> run(AgentContext ctx) {
    runCount += 1;
    if (!started.isCompleted) started.complete();
    return _result.future;
  }

  void complete(AgentRunResult result) {
    _result.complete(result);
  }
}

MemoryRuntime _runtime() {
  final db = makeTestDatabase();
  return _runtimeForDb(db);
}

MemoryRuntime _runtimeForDb(AppDatabase db) {
  return MemoryRuntime(
    embedder: StubEmbedder(),
    memoryStore: SqliteMemoryStore(db: db),
    eventStore: SqliteEventStore(db: db),
  );
}

final _refProvider = Provider<Ref>((ref) => ref);

AgentContext _context(MemoryRuntime rt, DateTime now) {
  // ProviderContainer keeps the Ref alive for the duration of the
  // test; the stub agents in this file never call `ref.read`, but the
  // AgentContext constructor requires a real Ref.
  final container = ProviderContainer();
  addTearDown(container.dispose);
  final ref = container.read(_refProvider);
  return AgentContext(ref: ref, now: now);
}

void main() {
  final now = DateTime.utc(2026, 5, 27, 14);

  test('AgentRunResult exposes user-visible status', () {
    final finishedAt = now.add(const Duration(milliseconds: 10));

    final completed = AgentRunResult(
      agentId: 'completed',
      status: AgentRunStatus.completed,
      startedAt: now,
      finishedAt: finishedAt,
    );
    final skipped = AgentRunResult.skipped(
      agentId: 'skipped',
      startedAt: now,
      finishedAt: finishedAt,
      reason: 'nothing new',
    );
    final failed = AgentRunResult.failed(
      agentId: 'failed',
      startedAt: now,
      finishedAt: finishedAt,
      error: 'boom',
    );

    expect(completed.userVisibleStatus, AgentRunUserVisibleStatus.ready);
    expect(skipped.userVisibleStatus, AgentRunUserVisibleStatus.noFinding);
    expect(failed.userVisibleStatus, AgentRunUserVisibleStatus.failed);
  });

  test('runOnce returns completed result + writes one event', () async {
    final rt = _runtime();
    final runner = AgentRunner(runtime: rt, ownerUserId: 'u');
    final agent = _StubAgent(
      id: 'stub',
      onRun: (ctx) => AgentRunResult(
        agentId: 'stub',
        status: AgentRunStatus.completed,
        startedAt: ctx.now,
        finishedAt: ctx.now.add(const Duration(milliseconds: 10)),
        summary: 'ok',
        memoryId: 'memory-1',
        artifactId: 'artifact-1',
        traceId: 'trace-1',
      ),
    );

    final result = await runner.runOnce(agent, _context(rt, now));
    expect(result.status, AgentRunStatus.completed);
    expect(agent.runCount, 1);

    final events = await rt.recentEvents(
      ownerUserId: 'u',
      window: const Duration(days: 9999),
    );
    expect(events, hasLength(1));
    expect(events.single.kind.name, kAgentRunEventTypeCompleted);
    expect(events.single.facts['agent_id'], 'stub');
    expect(events.single.facts['memory_id'], 'memory-1');
    expect(events.single.facts['artifact_id'], 'artifact-1');
    expect(events.single.facts['trace_id'], 'trace-1');
  });

  test('runOnce skips disabled agents without writing run history', () async {
    final rt = _runtime();
    final preferences = InMemoryAgentPreferenceStore();
    final runStore = InMemoryAgentRunStore();
    await preferences.setEnabled(
      ownerUserId: 'u',
      agentId: 'disabled',
      enabled: false,
      updatedAt: now,
    );
    final runner = AgentRunner(
      runtime: rt,
      ownerUserId: 'u',
      runStore: runStore,
      preferenceStore: preferences,
    );
    final agent = _StubAgent(id: 'disabled');

    final result = await runner.runOnce(agent, _context(rt, now));

    expect(result.status, AgentRunStatus.skipped);
    expect(result.summary, 'agent disabled');
    expect(agent.runCount, 0);
    expect(
      await runStore.latestForAgent(ownerUserId: 'u', agentId: 'disabled'),
      isNull,
    );
    final events = await rt.recentEvents(
      ownerUserId: 'u',
      window: const Duration(days: 9999),
    );
    expect(events, isEmpty);
  });

  test('runOnce captures throws as failed result', () async {
    final rt = _runtime();
    final runner = AgentRunner(runtime: rt, ownerUserId: 'u');
    final agent = _StubAgent(
      id: 'boom',
      throws: StateError('upstream offline'),
    );
    final result = await runner.runOnce(agent, _context(rt, now));
    expect(result.status, AgentRunStatus.failed);
    expect(result.error, contains('upstream offline'));
    final events = await rt.recentEvents(
      ownerUserId: 'u',
      window: const Duration(days: 9999),
    );
    expect(events.single.kind.name, kAgentRunEventTypeFailed);
  });

  test('lastRunAt advances after a successful run', () async {
    final rt = _runtime();
    final runner = AgentRunner(runtime: rt, ownerUserId: 'u');
    final agent = _StubAgent(id: 'stub');
    expect(await runner.lastRunAt('stub'), isNull);
    await runner.runOnce(agent, _context(rt, now));
    expect(
      await runner.lastRunAt('stub'),
      now.add(const Duration(milliseconds: 10)),
    );
  });

  test('failed runs do NOT advance lastRunAt', () async {
    final rt = _runtime();
    final runner = AgentRunner(runtime: rt, ownerUserId: 'u');
    final agent = _StubAgent(id: 'boom', throws: 'nope');
    await runner.runOnce(agent, _context(rt, now));
    expect(await runner.lastRunAt('boom'), isNull);
  });

  test('skipped runs advance lastRunAt so tick does not loop', () async {
    final rt = _runtime();
    final runner = AgentRunner(runtime: rt, ownerUserId: 'u');
    final agent = _StubAgent(
      id: 'quiet',
      onRun: (ctx) => AgentRunResult.skipped(
        agentId: 'quiet',
        startedAt: ctx.now,
        finishedAt: ctx.now.add(const Duration(milliseconds: 10)),
        reason: 'nothing new',
      ),
    );

    await runner.runOnce(agent, _context(rt, now));
    expect(
      await runner.lastRunAt('quiet'),
      now.add(const Duration(milliseconds: 10)),
    );

    final tooSoon = await runner.tick(
      agents: [agent],
      context: _context(rt, now.add(const Duration(minutes: 30))),
    );
    expect(tooSoon, isEmpty);
    expect(agent.runCount, 1);
  });

  test(
    'concurrent runOnce returns transient busy without advancing gates',
    () async {
      final rt = _runtime();
      final runStore = InMemoryAgentRunStore();
      final runner = AgentRunner(
        runtime: rt,
        ownerUserId: 'u',
        runStore: runStore,
      );
      final agent = _BlockingAgent(id: 'blocking');

      final first = runner.runOnce(agent, _context(rt, now));
      await agent.started.future;

      final busy = await runner.runOnce(
        agent,
        _context(rt, now.add(const Duration(milliseconds: 1))),
      );

      expect(busy.status, AgentRunStatus.busy);
      expect(agent.runCount, 1);
      expect(await runner.lastRunAt('blocking'), isNull);
      expect(
        await rt.recentEvents(
          ownerUserId: 'u',
          window: const Duration(days: 9999),
        ),
        isEmpty,
      );

      agent.complete(
        AgentRunResult(
          agentId: 'blocking',
          status: AgentRunStatus.completed,
          startedAt: now,
          finishedAt: now.add(const Duration(milliseconds: 10)),
          summary: 'done',
        ),
      );
      final completed = await first;

      expect(completed.status, AgentRunStatus.completed);
      expect(
        await runner.lastRunAt('blocking'),
        now.add(const Duration(milliseconds: 10)),
      );
      final latest = await runStore.latestForAgent(
        ownerUserId: 'u',
        agentId: 'blocking',
      );
      expect(latest?.status, AgentRunLifecycleStatus.ready);
      final events = await rt.recentEvents(
        ownerUserId: 'u',
        window: const Duration(days: 9999),
      );
      expect(events, hasLength(1));
    },
  );

  test('persisted run store gates a new runner instance', () async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final store = SqliteAgentRunStore(db: db);
    final rt = _runtimeForDb(db);
    final firstRunner = AgentRunner(
      runtime: rt,
      ownerUserId: 'u',
      runStore: store,
    );
    final secondRunner = AgentRunner(
      runtime: rt,
      ownerUserId: 'u',
      runStore: store,
    );
    final agent = _StubAgent(
      id: 'persisted',
      schedule: const AgentSchedule(interval: Duration(hours: 1)),
      onRun: (ctx) => AgentRunResult(
        agentId: 'persisted',
        status: AgentRunStatus.completed,
        startedAt: ctx.now,
        finishedAt: ctx.now.add(const Duration(minutes: 45)),
        summary: 'persisted ok',
        artifactId: 'artifact-persisted',
        traceId: 'trace-persisted',
      ),
    );

    await firstRunner.tick(agents: [agent], context: _context(rt, now));
    expect(agent.runCount, 1);

    final tooSoon = await secondRunner.tick(
      agents: [agent],
      context: _context(rt, now.add(const Duration(hours: 1, minutes: 30))),
    );

    expect(tooSoon, isEmpty);
    expect(agent.runCount, 1);
    final latest = await store.latestForAgent(
      ownerUserId: 'u',
      agentId: 'persisted',
    );
    expect(latest?.status, AgentRunLifecycleStatus.ready);
    expect(latest?.trigger, AgentRunTrigger.schedule);
    expect(latest?.artifactId, 'artifact-persisted');
    expect(latest?.traceId, 'trace-persisted');
  });

  test('persisted run store lists agent history newest first', () async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final store = SqliteAgentRunStore(db: db);
    final agent = _StubAgent(id: 'history');
    final first = DateTime.utc(2026, 5, 27, 9);
    final second = DateTime.utc(2026, 5, 28, 9);

    await store.markRunning(
      ownerUserId: 'u',
      agent: agent,
      startedAt: first,
      trigger: AgentRunTrigger.schedule,
    );
    await store.finishRun(
      ownerUserId: 'u',
      agent: agent,
      runStartedAt: first,
      result: AgentRunResult(
        agentId: agent.id,
        status: AgentRunStatus.completed,
        startedAt: first,
        finishedAt: first.add(const Duration(milliseconds: 10)),
        summary: 'first',
      ),
      trigger: AgentRunTrigger.schedule,
    );
    await store.markRunning(
      ownerUserId: 'u',
      agent: agent,
      startedAt: second,
      trigger: AgentRunTrigger.manual,
    );
    await store.finishRun(
      ownerUserId: 'u',
      agent: agent,
      runStartedAt: second,
      result: AgentRunResult.skipped(
        agentId: agent.id,
        startedAt: second,
        finishedAt: second.add(const Duration(milliseconds: 10)),
        reason: 'second',
      ),
      trigger: AgentRunTrigger.manual,
    );

    final history = await store.listForAgent(
      ownerUserId: 'u',
      agentId: agent.id,
    );
    final limited = await store.listForAgent(
      ownerUserId: 'u',
      agentId: agent.id,
      limit: 1,
    );

    expect(history.map((run) => run.summary), ['second', 'first']);
    expect(history.map((run) => run.trigger), [
      AgentRunTrigger.manual,
      AgentRunTrigger.schedule,
    ]);
    expect(limited.map((run) => run.summary), ['second']);
  });

  test('tick fires every agent whose schedule says yes', () async {
    final rt = _runtime();
    final runner = AgentRunner(runtime: rt, ownerUserId: 'u');
    final hourly = _StubAgent(
      id: 'hourly',
      schedule: const AgentSchedule(interval: Duration(hours: 1)),
    );
    final morning = _StubAgent(
      id: 'morning',
      schedule: AgentSchedule.daily(hourLocal: 7),
    );

    final beforeMorning = DateTime(2026, 5, 27, 6).toUtc();

    // 06:00 local — hourly fires, morning blocked by hour gate.
    final results = await runner.tick(
      agents: [hourly, morning],
      context: _context(rt, beforeMorning),
    );
    expect(results.map((r) => r.agentId).toList(), ['hourly']);
    expect(hourly.runCount, 1);
    expect(morning.runCount, 0);
  });

  test('tick respects interval after a previous fire', () async {
    final rt = _runtime();
    final runner = AgentRunner(runtime: rt, ownerUserId: 'u');
    final hourly = _StubAgent(
      id: 'hourly',
      schedule: const AgentSchedule(interval: Duration(hours: 1)),
    );

    await runner.tick(agents: [hourly], context: _context(rt, now));
    final tooSoon = await runner.tick(
      agents: [hourly],
      context: _context(rt, now.add(const Duration(minutes: 30))),
    );
    expect(tooSoon, isEmpty);
    expect(hourly.runCount, 1);

    final later = await runner.tick(
      agents: [hourly],
      context: _context(rt, now.add(const Duration(hours: 1, minutes: 1))),
    );
    expect(later, hasLength(1));
    expect(hourly.runCount, 2);
  });

  test('tick skips agents disabled in preferences', () async {
    final rt = _runtime();
    final preferences = InMemoryAgentPreferenceStore();
    final runner = AgentRunner(
      runtime: rt,
      ownerUserId: 'u',
      preferenceStore: preferences,
    );
    final agent = _StubAgent(
      id: 'disabled',
      schedule: const AgentSchedule(interval: Duration(hours: 1)),
    );
    await preferences.setEnabled(
      ownerUserId: 'u',
      agentId: 'disabled',
      enabled: false,
      updatedAt: now,
    );

    final results = await runner.tick(
      agents: [agent],
      context: _context(rt, now),
    );

    expect(results, isEmpty);
    expect(agent.runCount, 0);
  });

  test('AgentRunController runs registered agent by id', () async {
    final rt = _runtime();
    final runner = AgentRunner(runtime: rt, ownerUserId: 'u');
    final agent = _StubAgent(id: 'registered');
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final ref = container.read(_refProvider);
    final controller = AgentRunController(
      runner: runner,
      agents: [agent],
      ref: ref,
    );

    final result = await controller.runOnceById('registered', now: now);

    expect(result.status, AgentRunStatus.completed);
    expect(agent.runCount, 1);
  });

  test('AgentRunController ticks only selected registered agents', () async {
    final rt = _runtime();
    final runner = AgentRunner(runtime: rt, ownerUserId: 'u');
    final hourly = _StubAgent(
      id: 'hourly',
      schedule: const AgentSchedule(interval: Duration(hours: 1)),
    );
    final other = _StubAgent(
      id: 'other',
      schedule: const AgentSchedule(interval: Duration(hours: 1)),
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final ref = container.read(_refProvider);
    final controller = AgentRunController(
      runner: runner,
      agents: [hourly, other],
      ref: ref,
    );

    final results = await controller.tick(
      now: now,
      onlyAgentIds: const <String>['hourly'],
    );

    expect(results.map((result) => result.agentId), ['hourly']);
    expect(hourly.runCount, 1);
    expect(other.runCount, 0);
  });
}
