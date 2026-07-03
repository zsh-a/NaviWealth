import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/app/agent_runtime/bridges/agent_runtime_native_bridge.dart';
import 'package:naviwealth/app/agent_runtime/catalog/agent_runtime_catalog.dart';
import 'package:naviwealth/core/ai/agents/agent.dart';
import 'package:naviwealth/core/ai/contracts/memory_record.dart';
import 'package:naviwealth/core/ai/local/memory/memory_runtime.dart';
import 'package:naviwealth/core/ai/local/memory/providers.dart';
import 'package:naviwealth/core/ai/runtime/agent_runtime/agent_runtime_tool_plan_binding.dart';
import 'package:naviwealth/core/ai/runtime/device/device_tool_dispatcher.dart';
import 'package:naviwealth/core/ai/runtime/device/device_tool_session.dart';
import 'package:naviwealth/core/auth/current_user.dart';
import 'package:naviwealth/features/health/agents/weekly_summary_agent.dart';

import '../../../app/agent_runtime_tool_plan_test_harness.dart';

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
      final bridge = FakeAgentRuntimeToolPlanBridge();
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
        runtime: _runtime(
          bridge: FailingAgentRuntimeToolPlanBridge(),
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
            bridge: FakeAgentRuntimeToolPlanBridge(),
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

AgentRuntimeToolPlanBinding _runtime({
  required AgentRuntimeNativeBridge bridge,
  required DeviceToolDispatcher dispatcher,
  Future<void> Function(AgentRuntimeNativeStepRunResult stepRun)? recordTrace,
}) {
  return agentRuntimeToolPlanTestBinding(
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
  final calls = <AgentRuntimeToolPlanToolCall>[];

  @override
  Future<Object?> dispatch(
    DeviceToolSession session,
    String name,
    Object? input,
  ) async {
    calls.add(AgentRuntimeToolPlanToolCall(name, input));
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
