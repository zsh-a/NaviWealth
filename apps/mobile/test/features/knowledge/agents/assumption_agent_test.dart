import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/app/agent_runtime_catalog.dart';
import 'package:naviwealth/app/agent_runtime_native_bridge.dart';
import 'package:naviwealth/app/agent_runtime_tool_host.dart';
import 'package:naviwealth/core/ai/agents/agent.dart';
import 'package:naviwealth/core/ai/runtime/device/device_tool_dispatcher.dart';
import 'package:naviwealth/core/ai/runtime/device/device_tool_session.dart';
import 'package:naviwealth/features/knowledge/agents/assumption_agent.dart';

void main() {
  group('assumptionReviewItemsFromToolResult', () {
    test('parses list_open_assumptions output', () {
      final items = assumptionReviewItemsFromToolResult(const <String, Object?>{
        'assumptions': <Object?>[
          <String, Object?>{
            'id': 'assumption_1',
            'statement': 'Rates stay high',
            'days_since_verify': 91,
          },
        ],
      });

      expect(items, isNotNull);
      expect(items!.single.id, 'assumption_1');
      expect(items.single.daysSinceVerify, 91);
    });

    test('returns null for malformed output', () {
      final items = assumptionReviewItemsFromToolResult(const <String, Object?>{
        'assumptions': <Object?>[
          <String, Object?>{'id': 'assumption_1'},
        ],
      });

      expect(items, isNull);
    });
  });

  group('FrbAssumptionReviewReader', () {
    test(
      'reads assumptions through FRB list_open_assumptions tool plan',
      () async {
        final dispatcher = _AssumptionDispatcher();
        final bridge = _ToolPlanBridge();
        final traces = <AgentRuntimeNativeStepRunResult>[];
        final reader = FrbAssumptionReviewReader(
          stepRunner: AgentRuntimeNativeStepRunner(
            bridge: bridge,
            toolHost: AgentRuntimeToolHost(dispatcher: dispatcher),
          ),
          catalog: _catalog(),
          recordTrace: (stepRun) async => traces.add(stepRun),
        );

        final items = await reader.listOpen(_context());

        expect(items, hasLength(2));
        expect(items.first.id, 'assumption_stale');
        expect(dispatcher.calls.single.name, 'list_open_assumptions');
        expect(dispatcher.calls.single.input, containsPair('limit', 50));
        expect(
          bridge.startRequests.single.agentId,
          kKnowledgeAssumptionAgentId,
        );
        expect(
          bridge.startRequests.single.request['metadata'],
          containsPair('surface', 'knowledge_assumption'),
        );
        expect(traces.single.terminalStep['status'], 'completed');
        expect(traces.single.dispatchedToolCount, 1);
      },
    );

    test('falls back when FRB tool path fails', () async {
      final fallback = _FallbackReader(const <AssumptionReviewItem>[
        AssumptionReviewItem(
          id: 'fallback_assumption',
          statement: 'Fallback assumption',
          daysSinceVerify: 100,
        ),
      ]);
      final reader = FrbAssumptionReviewReader(
        stepRunner: AgentRuntimeNativeStepRunner(
          bridge: _FailingBridge(),
          toolHost: AgentRuntimeToolHost(dispatcher: _AssumptionDispatcher()),
        ),
        catalog: _catalog(),
        fallback: fallback,
      );

      final items = await reader.listOpen(_context());

      expect(items.single.id, 'fallback_assumption');
      expect(fallback.calls, 1);
    });

    test(
      'ignores trace recording failures after a successful FRB read',
      () async {
        final fallback = _FallbackReader(const <AssumptionReviewItem>[
          AssumptionReviewItem(
            id: 'fallback_assumption',
            statement: 'Fallback assumption',
            daysSinceVerify: 100,
          ),
        ]);
        final reader = FrbAssumptionReviewReader(
          stepRunner: AgentRuntimeNativeStepRunner(
            bridge: _ToolPlanBridge(),
            toolHost: AgentRuntimeToolHost(dispatcher: _AssumptionDispatcher()),
          ),
          catalog: _catalog(),
          fallback: fallback,
          recordTrace: (_) async => throw StateError('trace store unavailable'),
        );

        final items = await reader.listOpen(_context());

        expect(items, hasLength(2));
        expect(items.first.id, 'assumption_stale');
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

AgentRuntimeCatalog _catalog() {
  return AgentRuntimeCatalog(
    generatedAt: DateTime.utc(2026, 6, 29, 8),
    activeDomains: const <String>['knowledge'],
    agents: const <AgentRuntimeAgentSpec>[
      AgentRuntimeAgentSpec(
        id: kKnowledgeAssumptionAgentId,
        name: 'Assumption Review',
        version: '0.1.0',
        schedule: AgentRuntimeScheduleSpec.interval(everySeconds: 2592000),
        capabilities: <String>['scheduled_agent'],
        metadata: <String, Object?>{'domain': 'knowledge'},
      ),
    ],
    tools: const <AgentRuntimeToolSpec>[
      AgentRuntimeToolSpec(
        name: 'list_open_assumptions',
        description: 'List open assumptions',
        inputSchema: <String, Object?>{'type': 'object'},
        risk: 'read',
        metadata: <String, Object?>{'domain': 'knowledge'},
      ),
    ],
    proposalKinds: const <AgentRuntimeProposalKindSpec>[],
    promptBlocks: const <AgentRuntimePromptBlockSpec>[],
  );
}

class _AssumptionDispatcher implements DeviceToolDispatcher {
  final calls = <_ToolCall>[];

  @override
  Future<Object?> dispatch(
    DeviceToolSession session,
    String name,
    Object? input,
  ) async {
    calls.add(_ToolCall(name, input));
    return <String, Object?>{
      'assumptions': <Object?>[
        <String, Object?>{
          'id': 'assumption_stale',
          'statement': 'Rates stay high',
          'days_since_verify': 91,
        },
        <String, Object?>{
          'id': 'assumption_fresh',
          'statement': 'Demand holds',
          'days_since_verify': 7,
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

class _FallbackReader implements AssumptionReviewReader {
  _FallbackReader(this.result);

  final List<AssumptionReviewItem> result;
  var calls = 0;

  @override
  Future<List<AssumptionReviewItem>> listOpen(AgentContext ctx) async {
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
