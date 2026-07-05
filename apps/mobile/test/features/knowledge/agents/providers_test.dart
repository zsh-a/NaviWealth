import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/agents/agent.dart';
import 'package:naviwealth/core/ai/agents/agent_artifact.dart';
import 'package:naviwealth/core/ai/agents/agent_artifact_store.dart';
import 'package:naviwealth/core/ai/agents/agent_preference_store.dart';
import 'package:naviwealth/core/ai/agents/agent_run_controller.dart';
import 'package:naviwealth/core/ai/agents/agent_run_store.dart';
import 'package:naviwealth/core/ai/agents/providers.dart' as agent_providers;
import 'package:naviwealth/core/auth/current_user.dart';
import 'package:naviwealth/core/auth/domain_scope.dart';
import 'package:naviwealth/core/auth/providers.dart' as auth;
import 'package:naviwealth/core/background/background_scheduler.dart';
import 'package:naviwealth/core/background/providers.dart';
import 'package:naviwealth/core/persistence/providers.dart';
import 'package:naviwealth/design_system/preferences/theme_preferences.dart';
import 'package:naviwealth/features/knowledge/agents/assumption_agent.dart';
import 'package:naviwealth/features/knowledge/agents/providers.dart';
import 'package:naviwealth/features/knowledge/agents/review_agent.dart';
import 'package:naviwealth/features/knowledge/agents/routine_due_agent.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/persistence/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('routine due cron follows agent notification preference', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final db = makeTestDatabase();
    addTearDown(db.close);
    final scheduler = _RecordingScheduler();
    final c = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWith((_) async => db),
        sharedPreferencesProvider.overrideWithValue(prefs),
        backgroundSchedulerProvider.overrideWithValue(scheduler),
        currentUserIdProvider.overrideWith(
          (_) =>
              () async => 'user-1',
        ),
      ],
    );
    addTearDown(c.dispose);
    await c.read(auth.domainOptInsProvider.future);
    await c
        .read(auth.domainOptInsProvider.notifier)
        .setEnabled(DomainScope.knowledge, true);

    final sub = c.listen<void>(
      knowledgeRoutineDueCronProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(sub.close);
    await pumpEventQueue(times: 4);

    expect(scheduler.calls.last, 'register:$kKnowledgeRoutineDueTaskName');

    final preferenceStore = await c.read(
      agent_providers.agentPreferenceStoreProvider.future,
    );
    await preferenceStore.setNotificationsEnabled(
      ownerUserId: 'user-1',
      agentId: kKnowledgeRoutineAgentId,
      enabled: false,
      updatedAt: DateTime.utc(2026, 7, 5, 9),
    );
    final revision = c.read(
      agent_providers.agentPreferenceRevisionProvider.notifier,
    );
    revision.state = revision.state + 1;
    await pumpEventQueue(times: 4);

    expect(scheduler.calls.last, 'cancel:$kKnowledgeRoutineDueTaskName');
  });

  test(
    'pending routine due run consumes flag through shared catch-up',
    () async {
      final dueAt = DateTime.utc(2026, 7, 5, 8);
      SharedPreferences.setMockInitialValues(<String, Object>{
        kKnowledgeRoutineDueAtKey: dueAt.millisecondsSinceEpoch,
      });
      final prefs = await SharedPreferences.getInstance();
      final db = makeTestDatabase();
      addTearDown(db.close);
      final controller = _RecordingAgentRunController();
      final c = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWith((_) async => db),
          sharedPreferencesProvider.overrideWithValue(prefs),
          currentUserIdProvider.overrideWithValue(() async => 'user-1'),
          agent_providers.agentPreferenceStoreProvider.overrideWith(
            (_) async => InMemoryAgentPreferenceStore(),
          ),
          agentRunControllerProvider.overrideWith((_) async => controller),
        ],
      );
      addTearDown(c.dispose);
      await c.read(auth.domainOptInsProvider.future);
      await c
          .read(auth.domainOptInsProvider.notifier)
          .setEnabled(DomainScope.knowledge, true);

      final result = await c.read(pendingKnowledgeRoutineDueRunProvider.future);

      expect(result?.status, AgentRunStatus.completed);
      expect(controller.calls.single.agentId, kKnowledgeRoutineAgentId);
      expect(controller.calls.single.now, dueAt);
      expect(controller.calls.single.trigger, AgentRunTrigger.backgroundDue);
      expect(prefs.getInt(kKnowledgeRoutineDueAtKey), isNull);
    },
  );

  test('review result providers respect Knowledge opt-in', () async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final artifactStore = SqliteAgentArtifactStore(db: db);
    final runStore = SqliteAgentRunStore(db: db);
    final startedAt = DateTime.utc(2026, 7, 5, 9);
    await artifactStore.save(
      _knowledgeArtifact(id: 'knowledge-review-1', createdAt: startedAt),
    );
    await artifactStore.save(
      _knowledgeArtifact(
        id: 'knowledge-assumption-1',
        agentId: kKnowledgeAssumptionAgentId,
        createdAt: startedAt.add(const Duration(minutes: 5)),
      ),
    );
    await runStore.finishRun(
      ownerUserId: 'user-1',
      agent: const ReviewAgent(),
      runStartedAt: startedAt,
      result: AgentRunResult(
        agentId: kKnowledgeReviewAgentId,
        status: AgentRunStatus.completed,
        startedAt: startedAt,
        finishedAt: startedAt.add(const Duration(milliseconds: 20)),
        summary: 'Review due decisions',
        artifactId: 'knowledge-review-1',
        traceId: 'trace-knowledge-review',
      ),
      trigger: AgentRunTrigger.schedule,
    );
    final c = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWith((_) async => db),
        currentUserIdProvider.overrideWithValue(() async => 'user-1'),
        agent_providers.agentArtifactStoreProvider.overrideWith(
          (ref) async => artifactStore,
        ),
        agent_providers.agentRunStoreProvider.overrideWith(
          (ref) async => runStore,
        ),
      ],
    );
    addTearDown(c.dispose);
    await c.read(auth.domainOptInsProvider.future);

    expect(await c.read(latestKnowledgeReviewArtifactProvider.future), isNull);
    expect(
      await c.read(latestKnowledgeReviewArtifactsProvider.future),
      isEmpty,
    );
    expect(await c.read(latestKnowledgeReviewRunProvider.future), isNull);

    await c
        .read(auth.domainOptInsProvider.notifier)
        .setEnabled(DomainScope.knowledge, true);
    c.invalidate(latestKnowledgeReviewArtifactProvider);
    c.invalidate(latestKnowledgeReviewArtifactsProvider);
    c.invalidate(latestKnowledgeReviewRunProvider);

    final artifact = await c.read(latestKnowledgeReviewArtifactProvider.future);
    final artifacts = await c.read(
      latestKnowledgeReviewArtifactsProvider.future,
    );
    final run = await c.read(latestKnowledgeReviewRunProvider.future);

    expect(artifact?.id, 'knowledge-review-1');
    expect(artifacts.map((artifact) => artifact.id), [
      'knowledge-assumption-1',
      'knowledge-review-1',
    ]);
    expect(run?.status, AgentRunLifecycleStatus.ready);
    expect(run?.traceId, 'trace-knowledge-review');
  });
}

AgentArtifact _knowledgeArtifact({
  required String id,
  required DateTime createdAt,
  String agentId = kKnowledgeReviewAgentId,
}) {
  return AgentArtifact(
    id: id,
    ownerUserId: 'user-1',
    agentId: agentId,
    domain: 'knowledge',
    kind: AgentArtifactKind.review,
    severity: AgentArtifactSeverity.info,
    title: 'Knowledge Review',
    summary: 'Review due decisions',
    createdAt: createdAt,
  );
}

class _RecordingScheduler implements BackgroundScheduler {
  final List<String> calls = <String>[];

  @override
  Future<void> cancelTask(BackgroundTaskSpec task) async {
    calls.add('cancel:${task.name}');
  }

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<void> registerTask(
    BackgroundTaskSpec task, {
    Duration? interval,
  }) async {
    calls.add('register:${task.name}');
  }
}

class _RunCall {
  const _RunCall({
    required this.agentId,
    required this.now,
    required this.trigger,
  });

  final String agentId;
  final DateTime? now;
  final AgentRunTrigger trigger;
}

class _RecordingAgentRunController implements AgentRunController {
  final List<_RunCall> calls = <_RunCall>[];

  @override
  Future<AgentRunResult> runOnceById(
    String agentId, {
    DateTime? now,
    AgentRunTrigger trigger = AgentRunTrigger.manual,
  }) async {
    calls.add(_RunCall(agentId: agentId, now: now, trigger: trigger));
    final startedAt = now ?? DateTime.utc(2026, 7, 5, 8);
    return AgentRunResult(
      agentId: agentId,
      status: AgentRunStatus.completed,
      startedAt: startedAt,
      finishedAt: startedAt.add(const Duration(milliseconds: 1)),
      summary: 'background catch-up complete',
    );
  }

  @override
  Future<List<AgentRunResult>> tick({
    DateTime? now,
    Iterable<String>? onlyAgentIds,
    AgentRunTrigger trigger = AgentRunTrigger.schedule,
  }) async {
    throw UnimplementedError('tick is not used by this provider test');
  }
}
