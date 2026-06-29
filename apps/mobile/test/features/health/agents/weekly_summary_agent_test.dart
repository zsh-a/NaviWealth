import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/app/agent_runtime_catalog.dart';
import 'package:naviwealth/app/agent_runtime_native_bridge.dart';
import 'package:naviwealth/app/agent_runtime_tool_host.dart';
import 'package:naviwealth/core/ai/agents/agent.dart';
import 'package:naviwealth/core/ai/contracts/memory_record.dart';
import 'package:naviwealth/core/ai/local/memory/memory_runtime.dart';
import 'package:naviwealth/core/ai/local/memory/providers.dart';
import 'package:naviwealth/core/ai/runtime/device/device_session.dart';
import 'package:naviwealth/core/ai/runtime/device/device_tool_dispatcher.dart';
import 'package:naviwealth/core/auth/current_user.dart';
import 'package:naviwealth/features/health/agents/weekly_summary_agent.dart';

const _owner = 'u-health-weekly';

void main() {
  group('weeklySummarySnapshotFromTerminalStep', () {
    test('parses three-tool terminal output', () {
      final snapshot = weeklySummarySnapshotFromTerminalStep(
        const <String, Object?>{
          'status': 'completed',
          'output': <String, Object?>{
            'mode': 'frb_tool_loop',
            'tool_results': <Object?>[
              <String, Object?>{
                'tool_call': <String, Object?>{'name': 'get_recovery_signal'},
                'tool_response': <String, Object?>{
                  'result': <String, Object?>{'score': 82, 'verdict': 'rested'},
                },
              },
              <String, Object?>{
                'tool_call': <String, Object?>{
                  'name': 'get_recent_sleep_summary',
                },
                'tool_response': <String, Object?>{
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
                'tool_call': <String, Object?>{'name': 'get_activity_summary'},
                'tool_response': <String, Object?>{
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
      );

      expect(snapshot, isNotNull);
      expect(snapshot!.recoveryScore, 82);
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
          'output': <String, Object?>{'tool_results': <Object?>[]},
        },
      );

      expect(snapshot, isNull);
    });
  });

  group('FrbWeeklySummaryReader', () {
    test('reads weekly snapshot through a three-step FRB tool plan', () async {
      final dispatcher = _WeeklySummaryDispatcher();
      final bridge = _ToolPlanBridge();
      final traces = <AgentRuntimeNativeStepRunResult>[];
      final reader = FrbWeeklySummaryReader(
        stepRunner: AgentRuntimeNativeStepRunner(
          bridge: bridge,
          toolHost: AgentRuntimeToolHost(dispatcher: dispatcher),
        ),
        catalog: _catalog(),
        recordTrace: (stepRun) async => traces.add(stepRun),
      );

      final snapshot = await reader.read(_context());

      expect(snapshot.recoveryScore, 82);
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
      expect(traces.single.dispatchedToolCount, 3);
    });

    test('falls back when FRB tool path fails', () async {
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
        stepRunner: AgentRuntimeNativeStepRunner(
          bridge: _FailingBridge(),
          toolHost: AgentRuntimeToolHost(
            dispatcher: _WeeklySummaryDispatcher(),
          ),
        ),
        catalog: _catalog(),
        fallback: fallback,
      );

      final snapshot = await reader.read(_context());

      expect(snapshot.recoveryScore, 70);
      expect(fallback.calls, 1);
    });
  });

  test('writes weekly summary memory from reader snapshot', () async {
    final runtime = _FakeMemoryRuntime();
    final container = ProviderContainer(
      overrides: [
        currentUserIdProvider.overrideWithValue(() async => _owner),
        memoryRuntimeProvider.overrideWith((ref) async => runtime),
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
        ),
      ),
    );

    final result = await agent.run(
      AgentContext(ref: ref, now: DateTime.utc(2026, 6, 29, 20)),
    );

    expect(result.status, AgentRunStatus.completed);
    expect(result.summary, contains('Recovery 82/100 (rested)'));
    expect(result.summary, contains('42.0k steps'));
    expect(runtime.remembered?.source, kWeeklySummaryMemorySource);
  });
}

AgentContext _context() {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  final ref = container.read(_refProvider);
  return AgentContext(ref: ref, now: DateTime.utc(2026, 6, 29, 20));
}

final _refProvider = Provider<Ref>((ref) => ref);

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
        metadata: <String, Object?>{'domain': 'health'},
      ),
      AgentRuntimeToolSpec(
        name: 'get_recent_sleep_summary',
        description: 'Get sleep summary',
        inputSchema: <String, Object?>{'type': 'object'},
        risk: 'read',
        metadata: <String, Object?>{'domain': 'health'},
      ),
      AgentRuntimeToolSpec(
        name: 'get_activity_summary',
        description: 'Get activity summary',
        inputSchema: <String, Object?>{'type': 'object'},
        risk: 'read',
        metadata: <String, Object?>{'domain': 'health'},
      ),
    ],
    proposalKinds: const <AgentRuntimeProposalKindSpec>[],
    promptBlocks: const <AgentRuntimePromptBlockSpec>[],
  );
}

class _WeeklySummaryDispatcher implements DeviceToolDispatcher {
  final calls = <_ToolCall>[];

  @override
  Future<Object?> dispatch(
    DeviceSession session,
    String name,
    Object? input,
  ) async {
    calls.add(_ToolCall(name, input));
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

class _FakeMemoryRuntime implements MemoryRuntime {
  MemoryRecord? remembered;

  @override
  Future<void> remember(MemoryRecord record) async {
    remembered = record;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not stubbed');
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
