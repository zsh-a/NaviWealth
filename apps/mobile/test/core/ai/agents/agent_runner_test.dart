import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/agents/agent.dart';
import 'package:naviwealth/core/ai/agents/agent_runner.dart';
import 'package:naviwealth/core/ai/agents/agent_schedule.dart';
import 'package:naviwealth/core/ai/local/embedding/embedder.dart';
import 'package:naviwealth/core/ai/local/memory/event_store.dart';
import 'package:naviwealth/core/ai/local/memory/memory_runtime.dart';
import 'package:naviwealth/core/ai/local/memory/memory_store.dart';

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

MemoryRuntime _runtime() {
  final db = makeTestDatabase();
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

  test('runOnce returns completed result + writes one event', () async {
    final rt = _runtime();
    final runner = AgentRunner(runtime: rt, ownerUserId: 'u');
    final agent = _StubAgent(id: 'stub');

    final result = await runner.runOnce(agent, _context(rt, now));
    expect(result.status, AgentRunStatus.completed);
    expect(agent.runCount, 1);

    final events = await rt.recentEvents(
      ownerUserId: 'u',
      window: const Duration(days: 9999),
    );
    expect(events, hasLength(1));
    expect(events.single.type, kAgentRunEventTypeCompleted);
    expect(events.single.payload['agent_id'], 'stub');
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
    expect(events.single.type, kAgentRunEventTypeFailed);
  });

  test('lastRunAt advances after a successful run', () async {
    final rt = _runtime();
    final runner = AgentRunner(runtime: rt, ownerUserId: 'u');
    final agent = _StubAgent(id: 'stub');
    expect(runner.lastRunAt('stub'), isNull);
    await runner.runOnce(agent, _context(rt, now));
    expect(runner.lastRunAt('stub'), now);
  });

  test('failed runs do NOT advance lastRunAt', () async {
    final rt = _runtime();
    final runner = AgentRunner(runtime: rt, ownerUserId: 'u');
    final agent = _StubAgent(id: 'boom', throws: 'nope');
    await runner.runOnce(agent, _context(rt, now));
    expect(runner.lastRunAt('boom'), isNull);
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

    // 14:00 — hourly fires, morning blocked by hour gate.
    final results = await runner.tick(
      agents: [hourly, morning],
      context: _context(rt, now),
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
}
