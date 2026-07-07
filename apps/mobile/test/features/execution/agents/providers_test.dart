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
import 'package:naviwealth/features/execution/agents/providers.dart';
import 'package:naviwealth/features/execution/agents/review_agent.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/persistence/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'execution review cron follows agent enabled and notification preferences',
    () async {
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
          .setEnabled(DomainScope.execution, true);

      final sub = c.listen<void>(
        executionReviewCronProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(sub.close);
      await pumpEventQueue(times: 4);

      expect(scheduler.calls.last, 'register:$kExecutionReviewTaskName');

      final preferenceStore = await c.read(
        agent_providers.agentPreferenceStoreProvider.future,
      );
      await preferenceStore.setNotificationsEnabled(
        ownerUserId: 'user-1',
        agentId: kExecutionReviewAgentId,
        enabled: false,
        updatedAt: DateTime.utc(2026, 7, 5, 9),
      );
      final revision = c.read(
        agent_providers.agentPreferenceRevisionProvider.notifier,
      );
      revision.state = revision.state + 1;
      await pumpEventQueue(times: 4);

      expect(scheduler.calls.last, 'cancel:$kExecutionReviewTaskName');

      await preferenceStore.setNotificationsEnabled(
        ownerUserId: 'user-1',
        agentId: kExecutionReviewAgentId,
        enabled: true,
        updatedAt: DateTime.utc(2026, 7, 5, 10),
      );
      await preferenceStore.setEnabled(
        ownerUserId: 'user-1',
        agentId: kExecutionReviewAgentId,
        enabled: false,
        updatedAt: DateTime.utc(2026, 7, 5, 10),
      );
      revision.state = revision.state + 1;
      await pumpEventQueue(times: 4);

      expect(scheduler.calls.last, 'cancel:$kExecutionReviewTaskName');
    },
  );

  test(
    'pending execution review run consumes flag through shared catch-up',
    () async {
      final dueAt = DateTime.utc(2026, 7, 5, 8);
      SharedPreferences.setMockInitialValues(<String, Object>{
        kExecutionReviewDueAtKey: dueAt.millisecondsSinceEpoch,
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
          .setEnabled(DomainScope.execution, true);

      final result = await c.read(pendingExecutionReviewRunProvider.future);

      expect(result?.status, AgentRunStatus.completed);
      expect(controller.calls.single.agentId, kExecutionReviewAgentId);
      expect(controller.calls.single.now, dueAt);
      expect(controller.calls.single.trigger, AgentRunTrigger.backgroundDue);
      expect(prefs.getInt(kExecutionReviewDueAtKey), isNull);

      c.invalidate(pendingExecutionReviewRunProvider);
      final repeated = await c.read(pendingExecutionReviewRunProvider.future);

      expect(repeated, isNull);
      expect(controller.calls, hasLength(1));
    },
  );

  test('execution review providers read latest artifact and run', () async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final artifactStore = SqliteAgentArtifactStore(db: db);
    final runStore = SqliteAgentRunStore(db: db);
    final startedAt = DateTime.utc(2026, 7, 5, 17);
    await artifactStore.save(
      _executionArtifact(
        id: 'execution-review-old',
        createdAt: startedAt.subtract(const Duration(days: 7)),
      ),
    );
    await artifactStore.save(
      _executionArtifact(id: 'execution-review-new', createdAt: startedAt),
    );
    await runStore.finishRun(
      ownerUserId: 'user-1',
      agent: const ExecutionReviewAgent(),
      runStartedAt: startedAt,
      result: AgentRunResult(
        agentId: kExecutionReviewAgentId,
        status: AgentRunStatus.completed,
        startedAt: startedAt,
        finishedAt: startedAt.add(const Duration(milliseconds: 20)),
        summary: '3 actions need attention',
        artifactId: 'execution-review-new',
        traceId: 'trace-execution-review',
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
    await c
        .read(auth.domainOptInsProvider.notifier)
        .setEnabled(DomainScope.execution, true);

    final artifact = await c.read(latestExecutionReviewArtifactProvider.future);
    final run = await c.read(latestExecutionReviewRunProvider.future);

    expect(artifact?.id, 'execution-review-new');
    expect(run?.status, AgentRunLifecycleStatus.ready);
    expect(run?.artifactId, 'execution-review-new');
    expect(run?.traceId, 'trace-execution-review');
  });
}

AgentArtifact _executionArtifact({
  required String id,
  required DateTime createdAt,
}) {
  return AgentArtifact(
    id: id,
    ownerUserId: 'user-1',
    agentId: kExecutionReviewAgentId,
    domain: 'execution',
    kind: AgentArtifactKind.review,
    severity: AgentArtifactSeverity.info,
    title: 'Execution Review',
    summary: '3 actions need attention',
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
    Future<void> Function(Agent agent)? beforeRun,
  }) async {
    final agentId = onlyAgentIds?.single ?? kExecutionReviewAgentId;
    calls.add(_RunCall(agentId: agentId, now: now, trigger: trigger));
    final startedAt = now ?? DateTime.utc(2026, 7, 5, 8);
    return [
      AgentRunResult(
        agentId: agentId,
        status: AgentRunStatus.completed,
        startedAt: startedAt,
        finishedAt: startedAt.add(const Duration(milliseconds: 1)),
        summary: 'background catch-up complete',
      ),
    ];
  }
}
