import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/app/agent_runtime/bridges/agent_runtime_native_bridge.dart';
import 'package:naviwealth/app/agent_runtime/catalog/agent_runtime_catalog.dart';
import 'package:naviwealth/core/ai/agents/agent.dart';
import 'package:naviwealth/core/ai/agents/agent_artifact.dart';
import 'package:naviwealth/core/ai/agents/agent_artifact_store.dart';
import 'package:naviwealth/core/ai/agents/agent_presentation.dart';
import 'package:naviwealth/core/ai/agents/agent_registry.dart';
import 'package:naviwealth/core/ai/agents/agent_run_store.dart';
import 'package:naviwealth/core/ai/agents/providers.dart' as agent_providers;
import 'package:naviwealth/core/ai/regression/agent_outcome_evaluator.dart';
import 'package:naviwealth/core/ai/runtime/agent_runtime/agent_runtime_effect_plan_binding.dart';
import 'package:naviwealth/core/ai/runtime/device/device_tool_dispatcher.dart';
import 'package:naviwealth/core/ai/runtime/device/device_tool_session.dart';
import 'package:naviwealth/core/auth/current_user.dart';
import 'package:naviwealth/core/auth/domain_scope.dart';
import 'package:naviwealth/core/auth/providers.dart' as auth;
import 'package:naviwealth/core/lifeos/domain_pack.dart';
import 'package:naviwealth/core/persistence/providers.dart';
import 'package:naviwealth/features/health/agents/providers.dart'
    as health_agent_providers;
import 'package:naviwealth/features/health/agents/weekly_summary_agent.dart';

import '../../../app/agent_runtime_effect_plan_test_harness.dart';
import '../../../core/persistence/test_database.dart';

const _owner = 'u-health-weekly';

void main() {
  group('weeklySummarySnapshotFromTerminalStep', () {
    test('parses three-tool terminal output', () {
      final snapshot = weeklySummarySnapshotFromTerminalStep(
        const <String, Object?>{
          'status': 'completed',
          'output': <String, Object?>{
            'mode': 'frb_effect_loop',
            'effect_results': <Object?>[
              <String, Object?>{
                'effect': <String, Object?>{
                  'kind': 'tool',
                  'name': 'get_recovery_signal',
                },
                'effect_response': <String, Object?>{
                  'result': <String, Object?>{'score': 82, 'verdict': 'rested'},
                },
              },
              <String, Object?>{
                'effect': <String, Object?>{
                  'kind': 'tool',
                  'name': 'get_recent_sleep_summary',
                },
                'effect_response': <String, Object?>{
                  'result': <String, Object?>{
                    'sessions': <Object?>[
                      <String, Object?>{
                        'started_at': '2026-06-28T23:00:00.000Z',
                        'duration_hours': 7.5,
                      },
                    ],
                    'summary': <String, Object?>{
                      'session_count': 1,
                      'total_hours': 7.5,
                      'average_hours': 7.5,
                    },
                  },
                },
              },
              <String, Object?>{
                'effect': <String, Object?>{
                  'kind': 'tool',
                  'name': 'get_activity_summary',
                },
                'effect_response': <String, Object?>{
                  'result': <String, Object?>{
                    'days': <Object?>[
                      <String, Object?>{'date': '2026-06-28', 'steps': 9000},
                    ],
                    'summary': <String, Object?>{
                      'total_steps': 42000,
                      'workout_count': 3,
                      'workout_total_minutes': 95,
                    },
                  },
                },
              },
            ],
          },
        },
        traceId: 'trace-parser-1',
      );

      expect(snapshot, isNotNull);
      expect(snapshot!.traceId, 'trace-parser-1');
      expect(snapshot.recoveryScore, 82);
      expect(snapshot.recoveryVerdict, 'rested');
      expect(snapshot.avgSleepHours, 7.5);
      expect(snapshot.totalSteps, 42000);
      expect(snapshot.workoutCount, 3);
      expect(snapshot.workoutMinutes, 95);
    });

    test('returns null for malformed output', () {
      final snapshot = weeklySummarySnapshotFromTerminalStep(
        const <String, Object?>{
          'status': 'completed',
          'output': <String, Object?>{'effect_results': <Object?>[]},
        },
      );

      expect(snapshot, isNull);
    });
  });

  group('FrbWeeklySummaryReader', () {
    test(
      'reads weekly snapshot through a three-step FRB effect loop',
      () async {
        final dispatcher = _WeeklySummaryDispatcher();
        final bridge = FakeAgentRuntimeEffectPlanBridge();
        final traces = <AgentRuntimeNativeStepRunResult>[];
        final reader = FrbWeeklySummaryReader(
          runtime: _runtime(
            bridge: bridge,
            dispatcher: dispatcher,
            recordTrace: (stepRun) async => traces.add(stepRun),
          ),
        );

        final snapshot = await reader.read(_context());

        expect(snapshot.recoveryScore, 82);
        expect(snapshot.traceId, 'agent-runtime:weekly_summary:run_1');
        expect(snapshot.totalSteps, 42000);
        expect(dispatcher.calls.map((c) => c.name), <String>[
          'get_recovery_signal',
          'get_recent_sleep_summary',
          'get_activity_summary',
        ]);
        expect(bridge.startRequests.single.agentId, kWeeklySummaryAgentId);
        expect(
          bridge.startRequests.single.request['metadata'],
          containsPair('surface', 'health_weekly_summary'),
        );
        expect(traces.single.terminalStep['status'], 'completed');
        expect(traces.single.dispatchedEffectCount, 3);
      },
    );

    test('falls back when FRB effect path fails', () async {
      final fallback = _FallbackReader(
        const WeeklySummarySnapshot(
          hasHealthData: true,
          recoveryScore: 70,
          recoveryVerdict: 'balanced',
          avgSleepHours: 7,
          totalSteps: 1000,
          workoutCount: 0,
          workoutMinutes: 0,
        ),
      );
      final reader = FrbWeeklySummaryReader(
        runtime: _runtime(
          bridge: FailingAgentRuntimeEffectPlanBridge(),
          dispatcher: _WeeklySummaryDispatcher(),
        ),
        fallback: fallback,
      );

      final snapshot = await reader.read(_context());

      expect(snapshot.recoveryScore, 70);
      expect(fallback.calls, 1);
    });

    test(
      'ignores trace recording failures after a successful FRB read',
      () async {
        final fallback = _FallbackReader(
          const WeeklySummarySnapshot(
            hasHealthData: true,
            recoveryScore: 70,
            recoveryVerdict: 'balanced',
            avgSleepHours: 7,
            totalSteps: 1000,
            workoutCount: 0,
            workoutMinutes: 0,
          ),
        );
        final reader = FrbWeeklySummaryReader(
          runtime: _runtime(
            bridge: FakeAgentRuntimeEffectPlanBridge(),
            dispatcher: _WeeklySummaryDispatcher(),
            recordTrace: (_) async =>
                throw StateError('trace store unavailable'),
          ),
          fallback: fallback,
        );

        final snapshot = await reader.read(_context());

        expect(snapshot.recoveryScore, 82);
        expect(snapshot.totalSteps, 42000);
        expect(fallback.calls, 0);
      },
    );
  });

  test('writes weekly summary artifact from reader snapshot', () async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final store = SqliteAgentArtifactStore(db: db);
    final container = ProviderContainer(
      overrides: [
        currentUserIdProvider.overrideWithValue(() async => _owner),
        agent_providers.agentArtifactStoreProvider.overrideWith(
          (ref) async => store,
        ),
        ..._weeklySummaryRegistrationOverrides(),
      ],
    );
    addTearDown(container.dispose);
    final ref = container.read(_refProvider);
    final agent = WeeklySummaryAgent(
      summaryReader: _FallbackReader(
        const WeeklySummarySnapshot(
          hasHealthData: true,
          recoveryScore: 82,
          recoveryVerdict: 'rested',
          avgSleepHours: 7.5,
          totalSteps: 42000,
          workoutCount: 3,
          workoutMinutes: 95,
          traceId: 'trace-weekly-summary-1',
        ),
      ),
    );

    final result = await agent.run(
      AgentContext(ref: ref, now: DateTime.utc(2026, 6, 29, 20)),
    );

    expect(result.status, AgentRunStatus.completed);
    expect(result.summary, contains('Recovery 82/100 (rested)'));
    expect(result.summary, contains('42.0k steps'));
    expect(result.artifactId, '$kWeeklySummaryAgentId:2026-06-29');
    expect(result.traceId, 'trace-weekly-summary-1');
    expect(result.memoryId, isNull);

    final artifact = await store.read(result.artifactId!);
    expect(artifact, isNotNull);
    expect(artifact!.kind, AgentArtifactKind.review);
    expect(artifact.domain, 'health');
    expect(artifact.severity, AgentArtifactSeverity.info);
    expect(artifact.memoryId, isNull);
    expect(artifact.traceId, 'trace-weekly-summary-1');
    expect(artifact.summary, result.summary);
    expect(
      artifact.insights.map((insight) => insight.title),
      containsAll(['Recovery', 'Sleep', 'Activity', 'Workouts']),
    );
    expect(artifact.evidence.single.type, 'health_week');
    expect(artifact.actions.single.objectId, result.artifactId);

    final outcomeFailures = evaluateAgentOutcomeCase(
      regressionCase: agentOutcomeRegressionCaseById(
        'health.weekly_summary.ready',
      ),
      result: result,
      artifact: artifact,
    );
    expect(outcomeFailures, isEmpty, reason: outcomeFailures.join('\n'));
  });

  test(
    'latest weekly summary artifact provider returns newest health artifact',
    () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final store = SqliteAgentArtifactStore(db: db);
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWith((_) async => db),
          currentUserIdProvider.overrideWithValue(() async => _owner),
          agent_providers.agentArtifactStoreProvider.overrideWith(
            (ref) async => store,
          ),
          ..._weeklySummaryRegistrationOverrides(),
        ],
      );
      addTearDown(container.dispose);
      await container.read(auth.domainOptInsProvider.future);
      await container
          .read(auth.domainOptInsProvider.notifier)
          .setEnabled(DomainScope.health, true);
      await store.save(
        _weeklyArtifact(
          id: 'weekly-old',
          createdAt: DateTime.utc(2026, 6, 22, 20),
        ),
      );
      await store.save(
        _weeklyArtifact(
          id: 'weekly-new',
          createdAt: DateTime.utc(2026, 6, 29, 20),
        ),
      );

      final artifact = await container.read(
        health_agent_providers.latestWeeklySummaryArtifactProvider.future,
      );

      expect(artifact?.id, 'weekly-new');
    },
  );

  test(
    'latest weekly summary artifact provider respects Health opt-in',
    () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final store = SqliteAgentArtifactStore(db: db);
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWith((_) async => db),
          currentUserIdProvider.overrideWithValue(() async => _owner),
          agent_providers.agentArtifactStoreProvider.overrideWith(
            (ref) async => store,
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(auth.domainOptInsProvider.future);
      await store.save(
        _weeklyArtifact(
          id: 'weekly-hidden',
          createdAt: DateTime.utc(2026, 6, 29, 20),
        ),
      );

      final artifact = await container.read(
        health_agent_providers.latestWeeklySummaryArtifactProvider.future,
      );

      expect(artifact, isNull);
    },
  );

  test('latest weekly summary run provider returns last health run', () async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final runStore = SqliteAgentRunStore(db: db);
    final startedAt = DateTime.utc(2026, 6, 29, 20);
    final result = AgentRunResult.skipped(
      agentId: kWeeklySummaryAgentId,
      startedAt: startedAt,
      finishedAt: startedAt.add(const Duration(milliseconds: 20)),
      reason: 'no health data this week',
      traceId: 'trace-weekly-empty',
    );
    final outcomeFailures = evaluateAgentOutcomeCase(
      regressionCase: agentOutcomeRegressionCaseById(
        'health.weekly_summary.no_finding',
      ),
      result: result,
    );
    expect(outcomeFailures, isEmpty, reason: outcomeFailures.join('\n'));
    await runStore.finishRun(
      ownerUserId: _owner,
      agent: const WeeklySummaryAgent(),
      runStartedAt: startedAt,
      result: result,
      trigger: AgentRunTrigger.schedule,
    );
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWith((_) async => db),
        currentUserIdProvider.overrideWithValue(() async => _owner),
        agent_providers.agentRunStoreProvider.overrideWith(
          (ref) async => runStore,
        ),
        ..._weeklySummaryRegistrationOverrides(),
      ],
    );
    addTearDown(container.dispose);
    await container.read(auth.domainOptInsProvider.future);
    await container
        .read(auth.domainOptInsProvider.notifier)
        .setEnabled(DomainScope.health, true);

    final run = await container.read(
      health_agent_providers.latestWeeklySummaryRunProvider.future,
    );

    expect(run?.status, AgentRunLifecycleStatus.noFinding);
    expect(run?.summary, 'no health data this week');
    expect(run?.traceId, 'trace-weekly-empty');
  });
}

AgentContext _context() {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  final ref = container.read(_refProvider);
  return AgentContext(ref: ref, now: DateTime.utc(2026, 6, 29, 20));
}

final _refProvider = Provider<Ref>((ref) => ref);

List<Override> _weeklySummaryRegistrationOverrides() {
  return [
    agentRegistrationProvider.overrideWithValue(const <DomainAgentRegistration>[
      DomainAgentRegistration(
        agent: WeeklySummaryAgent(),
        domain: DomainScope.health,
      ),
    ]),
    agentPresentationSpecsProvider.overrideWithValue(
      const <String, AgentPresentationSpec>{
        kWeeklySummaryAgentId: AgentPresentationSpec(
          agentId: kWeeklySummaryAgentId,
          domain: DomainScope.health,
          icon: Icons.check,
          label: _agentLabel,
          description: _agentDescription,
          placement: AgentResultPlacement.domainReview,
        ),
      },
    ),
  ];
}

String _agentLabel(_) => 'Weekly Summary';

String _agentDescription(_) => 'Weekly Summary';

AgentArtifact _weeklyArtifact({
  required String id,
  required DateTime createdAt,
}) {
  return AgentArtifact(
    id: id,
    ownerUserId: _owner,
    agentId: kWeeklySummaryAgentId,
    domain: 'health',
    kind: AgentArtifactKind.review,
    severity: AgentArtifactSeverity.info,
    title: 'Weekly Summary',
    summary: 'Weekly health summary',
    createdAt: createdAt,
  );
}

AgentRuntimeEffectPlanBinding _runtime({
  required AgentRuntimeExecutionBridge bridge,
  required DeviceToolDispatcher dispatcher,
  Future<void> Function(AgentRuntimeNativeStepRunResult stepRun)? recordTrace,
}) {
  return agentRuntimeEffectPlanTestBinding(
    agentId: kWeeklySummaryAgentId,
    domain: 'health',
    surface: 'health_weekly_summary',
    bridge: bridge,
    dispatcher: dispatcher,
    catalog: _catalog(),
    recordTrace: recordTrace,
  );
}

AgentRuntimeCatalog _catalog() {
  return AgentRuntimeCatalog(
    generatedAt: DateTime.utc(2026, 6, 29, 20),
    activeDomains: const <String>['health'],
    agents: const <AgentRuntimeAgentSpec>[
      AgentRuntimeAgentSpec(
        id: kWeeklySummaryAgentId,
        name: 'Weekly Summary',
        version: '0.1.0',
        schedule: AgentRuntimeScheduleSpec.interval(everySeconds: 604800),
        capabilities: <String>['scheduled_agent'],
        metadata: <String, Object?>{'domain': 'health'},
      ),
    ],
    tools: const <AgentRuntimeToolSpec>[
      AgentRuntimeToolSpec(
        name: 'get_recovery_signal',
        description: 'Get recovery signal',
        inputSchema: <String, Object?>{'type': 'object'},
        risk: 'suggest',
        replayPolicy: 'safe_retry',
        metadata: <String, Object?>{'domain': 'health'},
      ),
      AgentRuntimeToolSpec(
        name: 'get_recent_sleep_summary',
        description: 'Get sleep summary',
        inputSchema: <String, Object?>{'type': 'object'},
        risk: 'read',
        replayPolicy: 'safe_retry',
        metadata: <String, Object?>{'domain': 'health'},
      ),
      AgentRuntimeToolSpec(
        name: 'get_activity_summary',
        description: 'Get activity summary',
        inputSchema: <String, Object?>{'type': 'object'},
        risk: 'read',
        replayPolicy: 'safe_retry',
        metadata: <String, Object?>{'domain': 'health'},
      ),
    ],
    proposalKinds: const <AgentRuntimeProposalKindSpec>[],
    promptBlocks: const <AgentRuntimePromptBlockSpec>[],
  );
}

class _WeeklySummaryDispatcher implements DeviceToolDispatcher {
  final calls = <AgentRuntimeEffectPlanToolEffect>[];

  @override
  Future<Object?> dispatch(
    DeviceToolSession session,
    String name,
    Object? input,
  ) async {
    calls.add(AgentRuntimeEffectPlanToolEffect(name, input));
    return switch (name) {
      'get_recovery_signal' => <String, Object?>{
        'score': 82,
        'verdict': 'rested',
      },
      'get_recent_sleep_summary' => <String, Object?>{
        'sessions': <Object?>[
          <String, Object?>{
            'started_at': '2026-06-28T23:00:00.000Z',
            'duration_hours': 7.5,
          },
        ],
        'summary': <String, Object?>{
          'session_count': 1,
          'total_hours': 7.5,
          'average_hours': 7.5,
        },
      },
      'get_activity_summary' => <String, Object?>{
        'days': <Object?>[
          <String, Object?>{'date': '2026-06-28', 'steps': 9000},
        ],
        'summary': <String, Object?>{
          'total_steps': 42000,
          'workout_count': 3,
          'workout_total_minutes': 95,
        },
      },
      _ => throw StateError('unexpected tool $name'),
    };
  }
}

class _FallbackReader implements WeeklySummaryReader {
  _FallbackReader(this.result);

  final WeeklySummarySnapshot result;
  var calls = 0;

  @override
  Future<WeeklySummarySnapshot> read(AgentContext ctx) async {
    calls += 1;
    return result;
  }
}
