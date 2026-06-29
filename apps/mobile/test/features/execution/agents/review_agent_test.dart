import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/app/agent_runtime_catalog.dart';
import 'package:naviwealth/app/agent_runtime_native_bridge.dart';
import 'package:naviwealth/app/agent_runtime_tool_host.dart';
import 'package:naviwealth/core/ai/agents/agent.dart';
import 'package:naviwealth/core/ai/contracts/memory_record.dart';
import 'package:naviwealth/core/ai/local/memory/providers.dart';
import 'package:naviwealth/core/ai/runtime/device/device_session.dart';
import 'package:naviwealth/core/ai/runtime/device/device_tool_dispatcher.dart';
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
  });

  group('executionReviewSnapshotFromTerminalStep', () {
    test('parses multi-tool terminal output', () {
      final snapshot = executionReviewSnapshotFromTerminalStep(
        const <String, Object?>{
          'status': 'completed',
          'output': <String, Object?>{
            'mode': 'frb_tool_loop',
            'tool_results': <Object?>[
              <String, Object?>{
                'tool_call': <String, Object?>{'name': 'list_open_actions'},
                'tool_response': <String, Object?>{
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
                'tool_call': <String, Object?>{
                  'name': 'summarize_execution_progress',
                },
                'tool_response': <String, Object?>{
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
      );

      expect(snapshot, isNotNull);
      expect(
        snapshot!.openActions.single.status,
        ExecutionActionStatus.blocked,
      );
      expect(snapshot.openActions.single.priority, ExecutionPriority.high);
      expect(snapshot.activeProjectCount, 1);
      expect(snapshot.activeProjects.single.id, 'project_1');
      expect(snapshot.recentProgress.single.id, 'progress_1');
    });

    test('returns null for malformed tool output', () {
      final snapshot = executionReviewSnapshotFromTerminalStep(
        const <String, Object?>{
          'status': 'completed',
          'output': <String, Object?>{'tool_results': <Object?>[]},
        },
      );

      expect(snapshot, isNull);
    });
  });

  group('FrbExecutionReviewReader', () {
    test('reads execution snapshot through a two-step FRB tool plan', () async {
      final dispatcher = _ExecutionDispatcher();
      final bridge = _ToolPlanBridge();
      final traces = <AgentRuntimeNativeStepRunResult>[];
      final reader = FrbExecutionReviewReader(
        stepRunner: AgentRuntimeNativeStepRunner(
          bridge: bridge,
          toolHost: AgentRuntimeToolHost(dispatcher: dispatcher),
        ),
        catalog: _catalog(),
        recordTrace: (stepRun) async => traces.add(stepRun),
      );

      final snapshot = await reader.read(_context());

      expect(snapshot.openActions.single.id, 'action_1');
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
      expect(traces.single.dispatchedToolCount, 2);
    });

    test('falls back when FRB tool path fails', () async {
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
        stepRunner: AgentRuntimeNativeStepRunner(
          bridge: _FailingBridge(),
          toolHost: AgentRuntimeToolHost(dispatcher: _ExecutionDispatcher()),
        ),
        catalog: _catalog(),
        fallback: fallback,
      );

      final snapshot = await reader.read(_context());

      expect(snapshot.openActions, isEmpty);
      expect(fallback.calls, 1);
    });
  });
}

AgentContext _context() {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  final ref = container.read(_refProvider);
  return AgentContext(ref: ref, now: DateTime.utc(2026, 6, 29, 8));
}

final _refProvider = Provider<Ref>((ref) => ref);

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
        metadata: <String, Object?>{'domain': 'execution'},
      ),
      AgentRuntimeToolSpec(
        name: 'summarize_execution_progress',
        description: 'Summarize execution progress',
        inputSchema: <String, Object?>{'type': 'object'},
        risk: 'suggest',
        metadata: <String, Object?>{'domain': 'execution'},
      ),
    ],
    proposalKinds: const <AgentRuntimeProposalKindSpec>[],
    promptBlocks: const <AgentRuntimePromptBlockSpec>[],
  );
}

class _ExecutionDispatcher implements DeviceToolDispatcher {
  final calls = <_ToolCall>[];

  @override
  Future<Object?> dispatch(
    DeviceSession session,
    String name,
    Object? input,
  ) async {
    calls.add(_ToolCall(name, input));
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

class _ToolPlanBridge implements AgentRuntimeNativeBridge {
  final startRequests = <_StartRequest>[];

  @override
  Future<String> protocolVersion() async => 'agent.v1';

  @override
  Future<String> catalogVersion() async => 'agent_catalog.v1';

  @override
  Future<Map<String, Object?>> catalogSummary(
    Map<String, Object?> catalog,
  ) async {
    return catalog;
  }

  @override
  Future<Map<String, Object?>> startRunStep({
    required Map<String, Object?> catalog,
    required Map<String, Object?> request,
    required String agentId,
  }) async {
    startRequests.add(_StartRequest(request: request, agentId: agentId));
    final input = request['input']! as Map<String, Object?>;
    final plan = input['tool_plan']! as List<Object?>;
    final first = plan.first! as Map<String, Object?>;
    return <String, Object?>{
      'protocol_version': 'agent.v1',
      'run_id': 'run_1',
      'agent_id': agentId,
      'status': 'tool_call_requested',
      'tool_call': <String, Object?>{
        'tool_call_id': 'call_1',
        'name': first['name'],
        'input': first['input'],
      },
      'continuation': <String, Object?>{
        'remaining_tool_plan': plan.skip(1).toList(growable: false),
        'tool_results': <Object?>[],
      },
    };
  }

  @override
  Future<Map<String, Object?>> continueRunStep({
    required Map<String, Object?> catalog,
    required Map<String, Object?> previousStep,
    required Map<String, Object?> toolResponse,
    required String agentId,
  }) async {
    final continuation = previousStep['continuation']! as Map<String, Object?>;
    final toolResults = <Object?>[
      ...(continuation['tool_results']! as List<Object?>),
      <String, Object?>{
        'tool_call': previousStep['tool_call'],
        'tool_response': toolResponse,
      },
    ];
    final remaining = continuation['remaining_tool_plan']! as List<Object?>;
    if (remaining.isNotEmpty) {
      final next = remaining.first! as Map<String, Object?>;
      return <String, Object?>{
        'protocol_version': 'agent.v1',
        'run_id': previousStep['run_id'],
        'agent_id': agentId,
        'status': 'tool_call_requested',
        'tool_call': <String, Object?>{
          'tool_call_id': 'call_${toolResults.length + 1}',
          'name': next['name'],
          'input': next['input'],
        },
        'continuation': <String, Object?>{
          'remaining_tool_plan': remaining.skip(1).toList(growable: false),
          'tool_results': toolResults,
        },
      };
    }
    return <String, Object?>{
      'protocol_version': 'agent.v1',
      'run_id': previousStep['run_id'],
      'agent_id': agentId,
      'status': 'completed',
      'output': <String, Object?>{
        'mode': 'frb_tool_loop',
        'tool_results': toolResults,
      },
    };
  }

  @override
  Future<Map<String, Object?>> completeMockLlm({
    required Map<String, Object?> request,
    required String responseText,
  }) async {
    return const <String, Object?>{};
  }

  @override
  Future<Map<String, Object?>> completeProfileLlm({
    required Map<String, Object?> request,
  }) async {
    return const <String, Object?>{};
  }

  @override
  Future<Map<String, Object?>> startProfileTurnStep({
    required Map<String, Object?> catalog,
    required Map<String, Object?> llmRequest,
    required String agentId,
    required Map<String, Object?> runMetadata,
  }) async {
    return const <String, Object?>{};
  }

  @override
  Future<Map<String, Object?>> validateLlmRequest(
    Map<String, Object?> request,
  ) async {
    return request;
  }

  @override
  Future<Map<String, Object?>> validateLlmResponse(
    Map<String, Object?> response,
  ) async {
    return response;
  }

  @override
  Future<Map<String, Object?>> validateRunRequest(
    Map<String, Object?> request,
  ) async {
    return request;
  }

  @override
  Future<Map<String, Object?>> validateToolSpec(
    Map<String, Object?> tool,
  ) async {
    return tool;
  }

  @override
  Future<Map<String, Object?>> validateTrace(Map<String, Object?> trace) async {
    return trace;
  }
}

class _FailingBridge extends _ToolPlanBridge {
  @override
  Future<Map<String, Object?>> startRunStep({
    required Map<String, Object?> catalog,
    required Map<String, Object?> request,
    required String agentId,
  }) async {
    throw StateError('native unavailable');
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

class _StartRequest {
  const _StartRequest({required this.request, required this.agentId});

  final Map<String, Object?> request;
  final String agentId;
}

class _ToolCall {
  const _ToolCall(this.name, this.input);

  final String name;
  final Object? input;
}
