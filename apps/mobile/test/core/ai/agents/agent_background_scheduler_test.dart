import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/agents/agent.dart';
import 'package:naviwealth/core/ai/agents/agent_background_scheduler.dart';
import 'package:naviwealth/core/ai/agents/agent_preference_store.dart';
import 'package:naviwealth/core/ai/agents/agent_run_controller.dart';
import 'package:naviwealth/core/ai/agents/agent_run_store.dart';
import 'package:naviwealth/core/ai/agents/agent_runner.dart';
import 'package:naviwealth/core/ai/agents/agent_schedule.dart';
import 'package:naviwealth/core/ai/local/embedding/embedder.dart';
import 'package:naviwealth/core/ai/local/memory/event_store.dart';
import 'package:naviwealth/core/ai/local/memory/memory_runtime.dart';
import 'package:naviwealth/core/ai/local/memory/memory_store.dart';
import 'package:naviwealth/core/background/background_scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/persistence/test_database.dart';

const _task = BackgroundTaskSpec(
  name: 'test.agent',
  dueAtPreferenceKey: 'test.agent.dueAt',
  defaultInterval: Duration(hours: 1),
);

final _refProvider = Provider<Ref>((ref) => ref);

class _StubAgent implements Agent {
  _StubAgent({
    this.schedule = const AgentSchedule(interval: Duration(hours: 1)),
  });

  @override
  String get id => 'agent-1';

  @override
  String get name => 'Agent One';

  @override
  final AgentSchedule schedule;

  var runCount = 0;

  @override
  Future<AgentRunResult> run(AgentContext ctx) async {
    runCount++;
    return AgentRunResult(
      agentId: id,
      status: AgentRunStatus.completed,
      startedAt: ctx.now,
      finishedAt: ctx.now.add(const Duration(milliseconds: 1)),
      summary: 'done',
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('AgentDueFlagStore consumes due flags once', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      _task.dueAtPreferenceKey: DateTime.utc(
        2026,
        7,
        5,
        8,
      ).millisecondsSinceEpoch,
    });
    final prefs = await SharedPreferences.getInstance();
    final store = AgentDueFlagStore(prefs: prefs);

    final dueAt = await store.consumeDue(_task);

    expect(dueAt, DateTime.utc(2026, 7, 5, 8));
    expect(await store.consumeDue(_task), isNull);
    expect(prefs.getInt(_task.dueAtPreferenceKey), isNull);
  });

  test('runIfDue executes agent through background_due trigger', () async {
    final dueAt = DateTime.utc(2026, 7, 5, 8);
    SharedPreferences.setMockInitialValues(<String, Object>{
      _task.dueAtPreferenceKey: dueAt.millisecondsSinceEpoch,
    });
    final prefs = await SharedPreferences.getInstance();
    final db = makeTestDatabase();
    addTearDown(db.close);
    final runtime = MemoryRuntime(
      embedder: StubEmbedder(),
      memoryStore: SqliteMemoryStore(db: db),
      eventStore: SqliteEventStore(db: db),
    );
    final runStore = SqliteAgentRunStore(db: db);
    final preferences = InMemoryAgentPreferenceStore();
    final runner = AgentRunner(
      runtime: runtime,
      ownerUserId: 'u',
      runStore: runStore,
      preferenceStore: preferences,
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final agent = _StubAgent();
    final controller = AgentRunController(
      runner: runner,
      agents: [agent],
      ref: container.read(_refProvider),
    );
    final catchUp = AgentBackgroundCatchUpRunner(
      dueFlags: AgentDueFlagStore(prefs: prefs),
      preferences: preferences,
      controller: controller,
      currentUserId: () async => 'u',
    );

    final result = await catchUp.runIfDue(
      binding: const AgentBackgroundTaskBinding(
        agentId: 'agent-1',
        task: _task,
      ),
    );

    expect(result?.status, AgentRunStatus.completed);
    expect(agent.runCount, 1);
    final latest = await runStore.latestForAgent(
      ownerUserId: 'u',
      agentId: 'agent-1',
    );
    expect(latest?.trigger, AgentRunTrigger.backgroundDue);
    expect(latest?.startedAt, dueAt);
  });

  test('runIfDue consumes flag but skips disabled agents', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      _task.dueAtPreferenceKey: DateTime.utc(
        2026,
        7,
        5,
        8,
      ).millisecondsSinceEpoch,
    });
    final prefs = await SharedPreferences.getInstance();
    final db = makeTestDatabase();
    addTearDown(db.close);
    final runtime = MemoryRuntime(
      embedder: StubEmbedder(),
      memoryStore: SqliteMemoryStore(db: db),
      eventStore: SqliteEventStore(db: db),
    );
    final preferences = InMemoryAgentPreferenceStore();
    await preferences.setEnabled(
      ownerUserId: 'u',
      agentId: 'agent-1',
      enabled: false,
      updatedAt: DateTime.utc(2026, 7, 5, 8),
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final agent = _StubAgent();
    final controller = AgentRunController(
      runner: AgentRunner(
        runtime: runtime,
        ownerUserId: 'u',
        preferenceStore: preferences,
      ),
      agents: [agent],
      ref: container.read(_refProvider),
    );
    final catchUp = AgentBackgroundCatchUpRunner(
      dueFlags: AgentDueFlagStore(prefs: prefs),
      preferences: preferences,
      controller: controller,
      currentUserId: () async => 'u',
    );

    final result = await catchUp.runIfDue(
      binding: const AgentBackgroundTaskBinding(
        agentId: 'agent-1',
        task: _task,
      ),
    );

    expect(result, isNull);
    expect(agent.runCount, 0);
    expect(prefs.getInt(_task.dueAtPreferenceKey), isNull);
  });

  test('runIfDue still runs notification-disabled agents', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      _task.dueAtPreferenceKey: DateTime.utc(
        2026,
        7,
        5,
        8,
      ).millisecondsSinceEpoch,
    });
    final prefs = await SharedPreferences.getInstance();
    final db = makeTestDatabase();
    addTearDown(db.close);
    final runtime = MemoryRuntime(
      embedder: StubEmbedder(),
      memoryStore: SqliteMemoryStore(db: db),
      eventStore: SqliteEventStore(db: db),
    );
    final preferences = InMemoryAgentPreferenceStore();
    await preferences.setNotificationsEnabled(
      ownerUserId: 'u',
      agentId: 'agent-1',
      enabled: false,
      updatedAt: DateTime.utc(2026, 7, 5, 8),
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final agent = _StubAgent();
    final controller = AgentRunController(
      runner: AgentRunner(
        runtime: runtime,
        ownerUserId: 'u',
        preferenceStore: preferences,
      ),
      agents: [agent],
      ref: container.read(_refProvider),
    );
    final catchUp = AgentBackgroundCatchUpRunner(
      dueFlags: AgentDueFlagStore(prefs: prefs),
      preferences: preferences,
      controller: controller,
      currentUserId: () async => 'u',
    );

    final result = await catchUp.runIfDue(
      binding: const AgentBackgroundTaskBinding(
        agentId: 'agent-1',
        task: _task,
      ),
    );

    expect(result?.status, AgentRunStatus.completed);
    expect(agent.runCount, 1);
    expect(prefs.getInt(_task.dueAtPreferenceKey), isNull);
  });

  test('runIfDue bypasses normal schedule gate for due flags', () async {
    final dueAt = DateTime.utc(2026, 7, 5, 8);
    SharedPreferences.setMockInitialValues(<String, Object>{
      _task.dueAtPreferenceKey: dueAt.millisecondsSinceEpoch,
    });
    final prefs = await SharedPreferences.getInstance();
    final db = makeTestDatabase();
    addTearDown(db.close);
    final runtime = MemoryRuntime(
      embedder: StubEmbedder(),
      memoryStore: SqliteMemoryStore(db: db),
      eventStore: SqliteEventStore(db: db),
    );
    final runStore = SqliteAgentRunStore(db: db);
    final preferences = InMemoryAgentPreferenceStore();
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final agent = _StubAgent(
      schedule: const AgentSchedule(interval: Duration(days: 365)),
    );
    final runner = AgentRunner(
      runtime: runtime,
      ownerUserId: 'u',
      runStore: runStore,
      preferenceStore: preferences,
    );
    final previous = dueAt.subtract(const Duration(days: 1));
    await runStore.markRunning(
      ownerUserId: 'u',
      agent: agent,
      startedAt: previous,
      trigger: AgentRunTrigger.schedule,
    );
    await runStore.finishRun(
      ownerUserId: 'u',
      agent: agent,
      runStartedAt: previous,
      result: AgentRunResult(
        agentId: agent.id,
        status: AgentRunStatus.completed,
        startedAt: previous,
        finishedAt: previous.add(const Duration(milliseconds: 1)),
        summary: 'previous',
      ),
      trigger: AgentRunTrigger.schedule,
    );
    final controller = AgentRunController(
      runner: runner,
      agents: [agent],
      ref: container.read(_refProvider),
    );
    final catchUp = AgentBackgroundCatchUpRunner(
      dueFlags: AgentDueFlagStore(prefs: prefs),
      preferences: preferences,
      controller: controller,
      currentUserId: () async => 'u',
    );

    final result = await catchUp.runIfDue(
      binding: const AgentBackgroundTaskBinding(
        agentId: 'agent-1',
        task: _task,
      ),
    );

    expect(result?.status, AgentRunStatus.completed);
    expect(agent.runCount, 1);
    final latest = await runStore.latestForAgent(
      ownerUserId: 'u',
      agentId: 'agent-1',
    );
    expect(latest?.trigger, AgentRunTrigger.backgroundDue);
  });
}
