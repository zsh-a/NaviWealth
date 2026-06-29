import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/app/agent_runtime_catalog.dart';
import 'package:naviwealth/app/agent_runtime_native_bridge.dart';
import 'package:naviwealth/app/agent_runtime_tool_host.dart';
import 'package:naviwealth/core/ai/agents/agent.dart';
import 'package:naviwealth/core/ai/runtime/device/device_session.dart';
import 'package:naviwealth/core/ai/runtime/device/device_tool_dispatcher.dart';
import 'package:naviwealth/features/knowledge/agents/routine_due_agent.dart';

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
      final bridge = _ToolPlanBridge();
      final traces = <AgentRuntimeNativeStepRunResult>[];
      final reader = FrbRoutineDueReader(
        stepRunner: AgentRuntimeNativeStepRunner(
          bridge: bridge,
          toolHost: AgentRuntimeToolHost(dispatcher: dispatcher),
        ),
        catalog: _catalog(),
        recordTrace: (stepRun) async => traces.add(stepRun),
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
        stepRunner: AgentRuntimeNativeStepRunner(
          bridge: _FailingBridge(),
          toolHost: AgentRuntimeToolHost(dispatcher: _RoutineDispatcher()),
        ),
        catalog: _catalog(),
        fallback: fallback,
      );

      final due = await reader.listDue(_context());

      expect(due.single.id, 'fallback_routine');
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
  final calls = <_ToolCall>[];

  @override
  Future<Object?> dispatch(
    DeviceSession session,
    String name,
    Object? input,
  ) async {
    calls.add(_ToolCall(name, input));
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
    final first = plan.single! as Map<String, Object?>;
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
    };
  }

  @override
  Future<Map<String, Object?>> continueRunStep({
    required Map<String, Object?> catalog,
    required Map<String, Object?> previousStep,
    required Map<String, Object?> toolResponse,
    required String agentId,
  }) async {
    return <String, Object?>{
      'protocol_version': 'agent.v1',
      'run_id': previousStep['run_id'],
      'agent_id': agentId,
      'status': 'completed',
      'output': <String, Object?>{
        'mode': 'frb_tool_step',
        'tool_result': toolResponse['result'],
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
