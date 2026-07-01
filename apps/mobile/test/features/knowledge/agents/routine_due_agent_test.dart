import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/app/agent_runtime_catalog.dart';
import 'package:naviwealth/app/agent_runtime_native_bridge.dart';
import 'package:naviwealth/app/agent_runtime_step_runner.dart';
import 'package:naviwealth/app/agent_runtime_tool_plan_binding.dart';
import 'package:naviwealth/core/ai/agents/agent.dart';
import 'package:naviwealth/core/ai/runtime/device/device_tool_dispatcher.dart';
import 'package:naviwealth/core/ai/runtime/device/device_tool_session.dart';
import 'package:naviwealth/features/knowledge/agents/routine_due_agent.dart';

import '../../../app/agent_runtime_tool_plan_test_harness.dart';

void main() {
  group('routineDueItemsFromToolResult', () {
    test('parses list_due_routines output', () {
      final items = routineDueItemsFromToolResult(const <String, Object?>{
        'routines': <Object?>[
          <String, Object?>{
            'id': 'routine_1',
            'statement': 'Activate bank card',
            'next_due_at': '2026-06-29T00:00:00.000Z',
          },
        ],
      });

      expect(items, isNotNull);
      expect(items!.single.id, 'routine_1');
      expect(items.single.statement, 'Activate bank card');
      expect(items.single.isDue(DateTime.utc(2026, 6, 29, 8)), isTrue);
    });

    test('returns null for malformed tool output', () {
      final items = routineDueItemsFromToolResult(const <String, Object?>{
        'routines': <Object?>[
          <String, Object?>{'id': 'routine_1'},
        ],
      });

      expect(items, isNull);
    });
  });

  group('FrbRoutineDueReader', () {
    test('reads routines through FRB list_due_routines tool plan', () async {
      final dispatcher = _RoutineDispatcher();
      final bridge = FakeAgentRuntimeToolPlanBridge();
      final traces = <AgentRuntimeNativeStepRunResult>[];
      final reader = FrbRoutineDueReader(
        runtime: _runtime(
          bridge: bridge,
          dispatcher: dispatcher,
          recordTrace: (stepRun) async => traces.add(stepRun),
        ),
      );

      final due = await reader.listDue(_context());

      expect(due, hasLength(1));
      expect(due.single.id, 'routine_1');
      expect(due.single.statement, 'Activate bank card');
      expect(dispatcher.calls.single.name, 'list_due_routines');
      expect(dispatcher.calls.single.input, containsPair('limit', 50));
      expect(bridge.startRequests.single.agentId, kKnowledgeRoutineAgentId);
      expect(
        bridge.startRequests.single.request['metadata'],
        containsPair('surface', 'knowledge_routine_due'),
      );
      expect(traces.single.terminalStep['status'], 'completed');
      expect(traces.single.dispatchedToolCount, 1);
    });

    test('falls back when FRB tool path fails', () async {
      final fallback = _FallbackReader(<RoutineDueItem>[
        RoutineDueItem(
          id: 'fallback_routine',
          statement: 'Fallback routine',
          nextDueAt: DateTime.utc(2026, 6, 30),
        ),
      ]);
      final reader = FrbRoutineDueReader(
        runtime: _runtime(
          bridge: FailingAgentRuntimeToolPlanBridge(),
          dispatcher: _RoutineDispatcher(),
        ),
        fallback: fallback,
      );

      final due = await reader.listDue(_context());

      expect(due.single.id, 'fallback_routine');
      expect(fallback.calls, 1);
    });

    test(
      'ignores trace recording failures after a successful FRB read',
      () async {
        final fallback = _FallbackReader(<RoutineDueItem>[
          RoutineDueItem(
            id: 'fallback_routine',
            statement: 'Fallback routine',
            nextDueAt: DateTime.utc(2026, 6, 30),
          ),
        ]);
        final reader = FrbRoutineDueReader(
          runtime: _runtime(
            bridge: FakeAgentRuntimeToolPlanBridge(),
            dispatcher: _RoutineDispatcher(),
            recordTrace: (_) async =>
                throw StateError('trace store unavailable'),
          ),
          fallback: fallback,
        );

        final due = await reader.listDue(_context());

        expect(due, hasLength(1));
        expect(due.single.id, 'routine_1');
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

AgentRuntimeToolPlanBinding _runtime({
  required AgentRuntimeNativeBridge bridge,
  required DeviceToolDispatcher dispatcher,
  Future<void> Function(AgentRuntimeNativeStepRunResult stepRun)? recordTrace,
}) {
  return agentRuntimeToolPlanTestBinding(
    agentId: kKnowledgeRoutineAgentId,
    domain: 'knowledge',
    surface: 'knowledge_routine_due',
    bridge: bridge,
    dispatcher: dispatcher,
    catalog: _catalog(),
    recordTrace: recordTrace,
  );
}

AgentRuntimeCatalog _catalog() {
  return AgentRuntimeCatalog(
    generatedAt: DateTime.utc(2026, 6, 29, 8),
    activeDomains: const <String>['knowledge'],
    agents: const <AgentRuntimeAgentSpec>[
      AgentRuntimeAgentSpec(
        id: kKnowledgeRoutineAgentId,
        name: 'Routine Due',
        version: '0.1.0',
        schedule: AgentRuntimeScheduleSpec.interval(everySeconds: 86400),
        capabilities: <String>['scheduled_agent'],
        metadata: <String, Object?>{'domain': 'knowledge'},
      ),
    ],
    tools: const <AgentRuntimeToolSpec>[
      AgentRuntimeToolSpec(
        name: 'list_due_routines',
        description: 'List due routines',
        inputSchema: <String, Object?>{'type': 'object'},
        risk: 'read',
        metadata: <String, Object?>{'domain': 'knowledge'},
      ),
    ],
    proposalKinds: const <AgentRuntimeProposalKindSpec>[],
    promptBlocks: const <AgentRuntimePromptBlockSpec>[],
  );
}

class _RoutineDispatcher implements DeviceToolDispatcher {
  final calls = <AgentRuntimeToolPlanToolCall>[];

  @override
  Future<Object?> dispatch(
    DeviceToolSession session,
    String name,
    Object? input,
  ) async {
    calls.add(AgentRuntimeToolPlanToolCall(name, input));
    return <String, Object?>{
      'as_of': '2026-07-06T08:00:00.000Z',
      'routines': <Object?>[
        <String, Object?>{
          'id': 'routine_1',
          'statement': 'Activate bank card',
          'interval_days': 180,
          'scope': 'personal',
          'next_due_at': '2026-06-29T00:00:00.000Z',
          'last_done_at': null,
          'days_until_due': 0,
        },
      ],
    };
  }
}

class _FallbackReader implements RoutineDueReader {
  _FallbackReader(this.result);

  final List<RoutineDueItem> result;
  var calls = 0;

  @override
  Future<List<RoutineDueItem>> listDue(AgentContext ctx) async {
    calls += 1;
    return result;
  }
}
