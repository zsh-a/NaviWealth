import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/app/agent_runtime/bridges/agent_runtime_native_bridge.dart';
import 'package:naviwealth/app/agent_runtime/catalog/agent_runtime_catalog.dart';
import 'package:naviwealth/core/ai/agents/agent.dart';
import 'package:naviwealth/core/ai/agents/agent_artifact.dart';
import 'package:naviwealth/core/ai/agents/agent_artifact_store.dart';
import 'package:naviwealth/core/ai/agents/agent_preference_store.dart';
import 'package:naviwealth/core/ai/agents/agent_run_store.dart';
import 'package:naviwealth/core/ai/agents/agent_runner.dart';
import 'package:naviwealth/core/ai/contracts/memory_record.dart';
import 'package:naviwealth/core/ai/local/memory/providers.dart';
import 'package:naviwealth/core/ai/regression/agent_outcome_evaluator.dart';
import 'package:naviwealth/core/ai/runtime/agent_runtime/agent_runtime_effect_plan_binding.dart';
import 'package:naviwealth/core/ai/runtime/device/device_tool_dispatcher.dart';
import 'package:naviwealth/core/ai/runtime/device/device_tool_session.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/persistence/providers.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/core/sync/outbox_provider.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/execution/agents/review_agent.dart';
import 'package:naviwealth/features/execution/data/providers.dart';
import 'package:naviwealth/features/execution/domain/execution_models.dart';

import '../../../app/agent_runtime_effect_plan_test_harness.dart';
import '../../../core/persistence/test_database.dart';

const _userId = 'u-exec-agent';
const _deviceId = 'dev-exec-agent';

Future<T> _withRef<T>(ProviderContainer c, Future<T> Function(Ref ref) body) {
  final probe = FutureProvider<T>((ref) => body(ref));
  c.listen(probe, (_, _) {});
  return c.read(probe.future);
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

MutationStamper _stamper() {
  var tick = 0;
  return MutationStamper(
    currentUserId: () async => _userId,
    deviceId: () async => _deviceId,
    stampHlc: () async {
      final meta = _sync(tick++);
      return meta.hlc;
    },
  );
}

ProviderContainer _container(AppDatabase db, InMemoryOutboxStore outbox) {
  return ProviderContainer(
    overrides: [
      appDatabaseProvider.overrideWith((ref) async => db),
      outboxStoreProvider.overrideWith((ref) async => outbox),
      currentUserIdProvider.overrideWithValue(() async => _userId),
      mutationStamperProvider.overrideWith((ref) async => _stamper()),
    ],
  );
}

void main() {
  late AppDatabase db;
  late InMemoryOutboxStore outbox;
  late ProviderContainer container;

  setUp(() {
    db = makeTestDatabase();
    outbox = InMemoryOutboxStore();
    container = _container(db, outbox);
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  test('writes weekly execution review memory from workflow signals', () async {
    final repo = await container.read(executionRepositoryProvider.future);
    await repo.upsertProject(
      ExecutionProject(
        id: 'project-review',
        title: 'Close execution workflow gaps',
        createdAt: DateTime.utc(2026, 6, 1),
        sync: _sync(1),
      ),
    );
    await repo.upsertCommitment(
      ExecutionCommitment(
        id: 'commit-review',
        title: 'Run weekly execution review',
        projectId: 'project-review',
        createdAt: DateTime.utc(2026, 6, 1),
        sync: _sync(2),
      ),
    );
    await repo.upsertAction(
      ExecutionAction(
        id: 'action-review',
        title: 'Finish review coverage',
        status: ExecutionActionStatus.blocked,
        priority: ExecutionPriority.high,
        projectId: 'project-review',
        commitmentId: 'commit-review',
        dueAt: DateTime.utc(2026, 6, 2),
        createdAt: DateTime.utc(2026, 6, 1),
        sync: _sync(3),
      ),
    );
    await repo.upsertProgress(
      ExecutionProgressEntry(
        id: 'progress-review',
        projectId: 'project-review',
        commitmentId: 'commit-review',
        kind: ExecutionProgressKind.checkin,
        note: 'Review workflow connected to memory.',
        createdAt: DateTime.utc(2026, 6, 3),
        sync: _sync(4),
      ),
    );

    final result = await _withRef(
      container,
      (ref) => const ExecutionReviewAgent().run(
        AgentContext(ref: ref, now: DateTime.utc(2026, 6, 5, 17)),
      ),
    );

    expect(result.status, AgentRunStatus.completed);
    expect(result.memoryId, '$kExecutionReviewMemorySource:2026-06-05');
    expect(result.artifactId, '$kExecutionReviewAgentId:2026-06-05');
    expect(result.summary, contains('1 blocked'));
    expect(result.summary, contains('1 active commitments'));

    final runtime = await container.read(memoryRuntimeProvider.future);
    final hits = await runtime.recall(
      ownerUserId: _userId,
      queryText: 'execution review blocked commitments',
      kinds: const {MemoryKind.episodic},
      source: kExecutionReviewMemorySource,
      topK: 5,
    );
    expect(hits, hasLength(1));
    expect(hits.single.record.entities, contains('execution_review'));
    expect(
      hits.single.record.entities,
      contains('execution_action:action-review'),
    );

    final artifact = await SqliteAgentArtifactStore(
      db: db,
    ).read('$kExecutionReviewAgentId:2026-06-05');
    expect(artifact, isNotNull);
    expect(artifact!.agentId, kExecutionReviewAgentId);
    expect(artifact.domain, 'execution');
    expect(artifact.kind, AgentArtifactKind.review);
    expect(artifact.severity, AgentArtifactSeverity.attention);
    expect(artifact.memoryId, result.memoryId);
    expect(artifact.summary, result.summary);
    expect(
      artifact.insights.map((insight) => insight.title),
      containsAll(['Today focus', 'Blocked work', 'Due work']),
    );
    expect(
      artifact.evidence.map((evidence) => evidence.id),
      contains('action-review'),
    );
    expect(artifact.actions.single.kind, 'review');
    final outcomeFailures = evaluateAgentOutcomeCase(
      regressionCase: agentOutcomeRegressionCaseById('execution.review.ready'),
      result: result,
      artifact: artifact,
    );
    expect(outcomeFailures, isEmpty, reason: outcomeFailures.join('\n'));
  });

  test('persists review trace id onto result, artifact, and memory', () async {
    final result = await _withRef(
      container,
      (ref) => ExecutionReviewAgent(
        reviewReader: _FallbackReader(
          ExecutionReviewSnapshot(
            openActions: [
              ExecutionReviewAction(
                id: 'action-trace',
                title: 'Trace execution review',
                status: ExecutionActionStatus.doing,
                priority: ExecutionPriority.high,
                dueAt: DateTime.utc(2026, 6, 5),
              ),
            ],
            activeProjects: const [ExecutionReviewRef(id: 'project-trace')],
            activeCommitments: const [
              ExecutionReviewRef(id: 'commitment-trace'),
            ],
            recentProgress: const [],
            activeProjectCount: 1,
            activeCommitmentCount: 1,
            traceId: 'trace-execution-1',
          ),
        ),
      ).run(AgentContext(ref: ref, now: DateTime.utc(2026, 6, 5, 17))),
    );

    expect(result.status, AgentRunStatus.completed);
    expect(result.traceId, 'trace-execution-1');

    final artifact = await SqliteAgentArtifactStore(
      db: db,
    ).read('$kExecutionReviewAgentId:2026-06-05');
    expect(artifact?.traceId, 'trace-execution-1');

    final runtime = await container.read(memoryRuntimeProvider.future);
    final hits = await runtime.recall(
      ownerUserId: _userId,
      queryText: 'trace execution review',
      kinds: const {MemoryKind.episodic},
      source: kExecutionReviewMemorySource,
      topK: 1,
    );
    expect(hits.single.record.payload['trace_id'], 'trace-execution-1');
    final outcome = hits.single.record.payload['outcome'] as Map;
    expect(outcome['trace_id'], 'trace-execution-1');
  });

  test('skips when there is nothing to review', () async {
    final result = await _withRef(
      container,
      (ref) => const ExecutionReviewAgent().run(
        AgentContext(ref: ref, now: DateTime.utc(2026, 6, 5, 17)),
      ),
    );

    expect(result.status, AgentRunStatus.skipped);
    expect(result.summary, 'no execution signals to review');
    final failures = evaluateAgentOutcomeCase(
      regressionCase: agentOutcomeRegressionCaseById(
        'execution.review.no_finding',
      ),
      result: result,
    );
    expect(failures, isEmpty, reason: failures.join('\n'));
  });

  test('budget exhausted runtime failure matches outcome corpus', () async {
    final runtime = await container.read(memoryRuntimeProvider.future);
    final runStore = SqliteAgentRunStore(db: db);
    final runner = AgentRunner(
      runtime: runtime,
      ownerUserId: _userId,
      runStore: runStore,
      preferenceStore: InMemoryAgentPreferenceStore(),
    );

    final result = await _withRef(
      container,
      (ref) => runner.runOnce(
        ExecutionReviewAgent(
          reviewReader: _ThrowingReader(StateError('effect_budget_exhausted')),
        ),
        AgentContext(ref: ref, now: DateTime.utc(2026, 6, 5, 17)),
      ),
    );

    expect(result.status, AgentRunStatus.failed);
    expect(result.error, contains('effect_budget_exhausted'));
    expect(result.artifactId, isNull);

    final outcomeFailures = evaluateAgentOutcomeCase(
      regressionCase: agentOutcomeRegressionCaseById(
        'execution.review.budget_exhausted',
      ),
      result: result,
    );
    expect(outcomeFailures, isEmpty, reason: outcomeFailures.join('\n'));
  });

  group('executionReviewSnapshotFromTerminalStep', () {
    test('parses multi-tool terminal output', () {
      final snapshot = executionReviewSnapshotFromTerminalStep(
        const <String, Object?>{
          'status': 'completed',
          'output': <String, Object?>{
            'mode': 'frb_effect_loop',
            'effect_results': <Object?>[
              <String, Object?>{
                'effect': <String, Object?>{
                  'kind': 'tool',
                  'name': 'list_open_actions',
                },
                'effect_response': <String, Object?>{
                  'result': <String, Object?>{
                    'actions': <Object?>[
                      <String, Object?>{
                        'id': 'action_1',
                        'title': 'Ship FRB review',
                        'status': 'blocked',
                        'priority': 'high',
                        'due_at': '2026-06-29T08:00:00.000Z',
                        'scheduled_for': null,
                      },
                    ],
                  },
                },
              },
              <String, Object?>{
                'effect': <String, Object?>{
                  'kind': 'tool',
                  'name': 'summarize_execution_progress',
                },
                'effect_response': <String, Object?>{
                  'result': <String, Object?>{
                    'active_project_count': 1,
                    'active_commitment_count': 1,
                    'active_projects': <Object?>[
                      <String, Object?>{'id': 'project_1'},
                    ],
                    'active_commitments': <Object?>[
                      <String, Object?>{'id': 'commitment_1'},
                    ],
                    'recent_progress': <Object?>[
                      <String, Object?>{
                        'id': 'progress_1',
                        'created_at': '2026-06-28T08:00:00.000Z',
                      },
                    ],
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
      expect(snapshot.openActions.single.status, ExecutionActionStatus.blocked);
      expect(snapshot.openActions.single.priority, ExecutionPriority.high);
      expect(snapshot.activeProjectCount, 1);
      expect(snapshot.activeProjects.single.id, 'project_1');
      expect(snapshot.recentProgress.single.id, 'progress_1');
    });

    test('returns null for malformed tool output', () {
      final snapshot = executionReviewSnapshotFromTerminalStep(
        const <String, Object?>{
          'status': 'completed',
          'output': <String, Object?>{'effect_results': <Object?>[]},
        },
      );

      expect(snapshot, isNull);
    });
  });

  group('FrbExecutionReviewReader', () {
    test(
      'reads execution snapshot through a two-step FRB effect loop',
      () async {
        final dispatcher = _ExecutionDispatcher();
        final bridge = FakeAgentRuntimeEffectPlanBridge();
        final traces = <AgentRuntimeNativeStepRunResult>[];
        final reader = FrbExecutionReviewReader(
          runtime: _runtime(
            bridge: bridge,
            dispatcher: dispatcher,
            recordTrace: (stepRun) async => traces.add(stepRun),
          ),
        );

        final snapshot = await reader.read(_context());

        expect(snapshot.openActions.single.id, 'action_1');
        expect(snapshot.traceId, 'agent-runtime:execution_review:run_1');
        expect(snapshot.activeProjectCount, 1);
        expect(dispatcher.calls.map((c) => c.name), <String>[
          'list_open_actions',
          'summarize_execution_progress',
        ]);
        expect(dispatcher.calls.first.input, containsPair('limit', 100));
        expect(bridge.startRequests.single.agentId, kExecutionReviewAgentId);
        expect(
          bridge.startRequests.single.request['metadata'],
          containsPair('surface', 'execution_review'),
        );
        expect(traces.single.terminalStep['status'], 'completed');
        expect(traces.single.dispatchedEffectCount, 2);
      },
    );

    test('falls back when FRB effect path fails', () async {
      final fallback = _FallbackReader(
        const ExecutionReviewSnapshot(
          openActions: <ExecutionReviewAction>[],
          activeProjects: <ExecutionReviewRef>[],
          activeCommitments: <ExecutionReviewRef>[],
          recentProgress: <ExecutionReviewProgress>[],
          activeProjectCount: 0,
          activeCommitmentCount: 0,
        ),
      );
      final reader = FrbExecutionReviewReader(
        runtime: _runtime(
          bridge: FailingAgentRuntimeEffectPlanBridge(),
          dispatcher: _ExecutionDispatcher(),
        ),
        fallback: fallback,
      );

      final snapshot = await reader.read(_context());

      expect(snapshot.openActions, isEmpty);
      expect(fallback.calls, 1);
    });

    test(
      'ignores trace recording failures after a successful FRB read',
      () async {
        final fallback = _FallbackReader(
          const ExecutionReviewSnapshot(
            openActions: <ExecutionReviewAction>[],
            activeProjects: <ExecutionReviewRef>[],
            activeCommitments: <ExecutionReviewRef>[],
            recentProgress: <ExecutionReviewProgress>[],
            activeProjectCount: 0,
            activeCommitmentCount: 0,
          ),
        );
        final reader = FrbExecutionReviewReader(
          runtime: _runtime(
            bridge: FakeAgentRuntimeEffectPlanBridge(),
            dispatcher: _ExecutionDispatcher(),
            recordTrace: (_) async =>
                throw StateError('trace store unavailable'),
          ),
          fallback: fallback,
        );

        final snapshot = await reader.read(_context());

        expect(snapshot.openActions.single.id, 'action_1');
        expect(snapshot.activeProjectCount, 1);
        expect(fallback.calls, 0);
      },
    );
  });
}

AgentContext _context() {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  final ref = container.read(_refProvider);
  return AgentContext(ref: ref, now: DateTime.utc(2026, 6, 29, 8));
}

final _refProvider = Provider<Ref>((ref) => ref);

AgentRuntimeEffectPlanBinding _runtime({
  required AgentRuntimeExecutionBridge bridge,
  required DeviceToolDispatcher dispatcher,
  Future<void> Function(AgentRuntimeNativeStepRunResult stepRun)? recordTrace,
}) {
  return agentRuntimeEffectPlanTestBinding(
    agentId: kExecutionReviewAgentId,
    domain: 'execution',
    surface: 'execution_review',
    bridge: bridge,
    dispatcher: dispatcher,
    catalog: _catalog(),
    recordTrace: recordTrace,
  );
}

AgentRuntimeCatalog _catalog() {
  return AgentRuntimeCatalog(
    generatedAt: DateTime.utc(2026, 6, 29, 8),
    activeDomains: const <String>['execution'],
    agents: const <AgentRuntimeAgentSpec>[
      AgentRuntimeAgentSpec(
        id: kExecutionReviewAgentId,
        name: 'Execution Review',
        version: '0.1.0',
        schedule: AgentRuntimeScheduleSpec.interval(everySeconds: 604800),
        capabilities: <String>['scheduled_agent'],
        metadata: <String, Object?>{'domain': 'execution'},
      ),
    ],
    tools: const <AgentRuntimeToolSpec>[
      AgentRuntimeToolSpec(
        name: 'list_open_actions',
        description: 'List open actions',
        inputSchema: <String, Object?>{'type': 'object'},
        risk: 'read',
        replayPolicy: 'safe_retry',
        metadata: <String, Object?>{'domain': 'execution'},
      ),
      AgentRuntimeToolSpec(
        name: 'summarize_execution_progress',
        description: 'Summarize execution progress',
        inputSchema: <String, Object?>{'type': 'object'},
        risk: 'suggest',
        replayPolicy: 'safe_retry',
        metadata: <String, Object?>{'domain': 'execution'},
      ),
    ],
    proposalKinds: const <AgentRuntimeProposalKindSpec>[],
    promptBlocks: const <AgentRuntimePromptBlockSpec>[],
  );
}

class _ExecutionDispatcher implements DeviceToolDispatcher {
  final calls = <AgentRuntimeEffectPlanToolEffect>[];

  @override
  Future<Object?> dispatch(
    DeviceToolSession session,
    String name,
    Object? input,
  ) async {
    calls.add(AgentRuntimeEffectPlanToolEffect(name, input));
    return switch (name) {
      'list_open_actions' => <String, Object?>{
        'actions': <Object?>[
          <String, Object?>{
            'id': 'action_1',
            'title': 'Ship FRB review',
            'status': 'doing',
            'priority': 'high',
            'due_at': '2026-06-29T08:00:00.000Z',
            'scheduled_for': null,
          },
        ],
      },
      'summarize_execution_progress' => <String, Object?>{
        'open_action_count': 1,
        'blocked_action_count': 0,
        'active_project_count': 1,
        'active_commitment_count': 1,
        'active_projects': <Object?>[
          <String, Object?>{'id': 'project_1'},
        ],
        'active_commitments': <Object?>[
          <String, Object?>{'id': 'commitment_1'},
        ],
        'recent_progress': <Object?>[
          <String, Object?>{
            'id': 'progress_1',
            'created_at': '2026-06-28T08:00:00.000Z',
          },
        ],
      },
      _ => throw StateError('unexpected tool $name'),
    };
  }
}

class _FallbackReader implements ExecutionReviewReader {
  _FallbackReader(this.result);

  final ExecutionReviewSnapshot result;
  var calls = 0;

  @override
  Future<ExecutionReviewSnapshot> read(AgentContext ctx) async {
    calls += 1;
    return result;
  }
}

class _ThrowingReader implements ExecutionReviewReader {
  const _ThrowingReader(this.error);

  final Object error;

  @override
  Future<ExecutionReviewSnapshot> read(AgentContext ctx) async {
    throw error;
  }
}
