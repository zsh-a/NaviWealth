import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/app/agent_runtime_catalog.dart';
import 'package:naviwealth/app/agent_runtime_native_bridge.dart';
import 'package:naviwealth/app/agent_runtime_tool_host.dart';
import 'package:naviwealth/core/ai/agents/agent.dart';
import 'package:naviwealth/core/ai/runtime/device/device_tool_dispatcher.dart';
import 'package:naviwealth/core/ai/runtime/device/device_tool_session.dart';
import 'package:naviwealth/features/knowledge/agents/assumption_agent.dart';
import 'package:naviwealth/features/knowledge/agents/review_agent.dart';

void main() {
  group('review due tool-result parsing', () {
    test('parses terminal multi-tool output and filters stale assumptions', () {
      final snapshot = reviewDueSnapshotFromTerminalStep(
        const <String, Object?>{
          'status': 'completed',
          'output': <String, Object?>{
            'mode': 'frb_tool_loop',
            'tool_results': <Object?>[
              <String, Object?>{
                'tool_call': <String, Object?>{'name': 'list_due_reviews'},
                'tool_response': <String, Object?>{
                  'result': <String, Object?>{
                    'decisions': <Object?>[
                      <String, Object?>{
                        'id': 'decision_1',
                        'question': 'Revisit portfolio hedge?',
                      },
                    ],
                  },
                },
              },
              <String, Object?>{
                'tool_call': <String, Object?>{'name': 'list_open_assumptions'},
                'tool_response': <String, Object?>{
                  'result': <String, Object?>{
                    'assumptions': <Object?>[
                      <String, Object?>{
                        'id': 'assumption_stale',
                        'statement': 'Rates stay high',
                        'days_since_verify': kAssumptionStaleDays,
                      },
                      <String, Object?>{
                        'id': 'assumption_fresh',
                        'statement': 'Demand holds',
                        'days_since_verify': 3,
                      },
                    ],
                  },
                },
              },
            ],
          },
        },
        now: DateTime.utc(2026, 6, 29),
      );

      expect(snapshot, isNotNull);
      expect(snapshot!.dueReviews.single.id, 'decision_1');
      expect(snapshot.staleAssumptions.single.id, 'assumption_stale');
    });

    test('returns null for malformed tool output', () {
      final snapshot = reviewDueSnapshotFromTerminalStep(
        const <String, Object?>{
          'status': 'completed',
          'output': <String, Object?>{'tool_results': <Object?>[]},
        },
        now: DateTime.utc(2026, 6, 29),
      );

      expect(snapshot, isNull);
    });
  });

  group('FrbReviewDueReader', () {
    test('reads review inputs through a two-step FRB tool plan', () async {
      final dispatcher = _ReviewDispatcher();
      final bridge = _ToolPlanBridge();
      final traces = <AgentRuntimeNativeStepRunResult>[];
      final reader = FrbReviewDueReader(
        stepRunner: AgentRuntimeNativeStepRunner(
          bridge: bridge,
          toolHost: AgentRuntimeToolHost(dispatcher: dispatcher),
        ),
        catalog: _catalog(),
        recordTrace: (stepRun) async => traces.add(stepRun),
      );

      final snapshot = await reader.read(_context());

      expect(snapshot.dueReviews.single.question, 'Revisit portfolio hedge?');
      expect(snapshot.staleAssumptions.single.statement, 'Rates stay high');
      expect(dispatcher.calls.map((c) => c.name), <String>[
        'list_due_reviews',
        'list_open_assumptions',
      ]);
      expect(
        dispatcher.calls.first.input,
        containsPair('as_of', '2026-06-29T08:00:00.000Z'),
      );
      expect(bridge.startRequests.single.agentId, kKnowledgeReviewAgentId);
      expect(
        bridge.startRequests.single.request['metadata'],
        containsPair('surface', 'knowledge_review'),
      );
      expect(traces.single.terminalStep['status'], 'completed');
      expect(traces.single.dispatchedToolCount, 2);
    });

    test('falls back when the FRB path fails', () async {
      final fallback = _FallbackReader(
        const ReviewDueSnapshot(
          dueReviews: <ReviewDecisionItem>[
            ReviewDecisionItem(id: 'fallback_decision', question: 'Fallback?'),
          ],
          staleAssumptions: <ReviewAssumptionItem>[],
        ),
      );
      final reader = FrbReviewDueReader(
        stepRunner: AgentRuntimeNativeStepRunner(
          bridge: _FailingBridge(),
          toolHost: AgentRuntimeToolHost(dispatcher: _ReviewDispatcher()),
        ),
        catalog: _catalog(),
        fallback: fallback,
      );

      final snapshot = await reader.read(_context());

      expect(snapshot.dueReviews.single.id, 'fallback_decision');
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
        id: kKnowledgeReviewAgentId,
        name: 'Weekly Review',
        version: '0.1.0',
        schedule: AgentRuntimeScheduleSpec.interval(everySeconds: 604800),
        capabilities: <String>['scheduled_agent'],
        metadata: <String, Object?>{'domain': 'knowledge'},
      ),
    ],
    tools: const <AgentRuntimeToolSpec>[
      AgentRuntimeToolSpec(
        name: 'list_due_reviews',
        description: 'List due reviews',
        inputSchema: <String, Object?>{'type': 'object'},
        risk: 'read',
        metadata: <String, Object?>{'domain': 'knowledge'},
      ),
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

class _ReviewDispatcher implements DeviceToolDispatcher {
  final calls = <_ToolCall>[];

  @override
  Future<Object?> dispatch(
    DeviceToolSession session,
    String name,
    Object? input,
  ) async {
    calls.add(_ToolCall(name, input));
    return switch (name) {
      'list_due_reviews' => <String, Object?>{
        'decisions': <Object?>[
          <String, Object?>{
            'id': 'decision_1',
            'question': 'Revisit portfolio hedge?',
            'status': 'active',
          },
        ],
      },
      'list_open_assumptions' => <String, Object?>{
        'assumptions': <Object?>[
          <String, Object?>{
            'id': 'assumption_stale',
            'statement': 'Rates stay high',
            'days_since_verify': kAssumptionStaleDays + 1,
          },
          <String, Object?>{
            'id': 'assumption_fresh',
            'statement': 'Demand holds',
            'days_since_verify': 7,
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
    final toolResults = <Object?>[
      ...((previousStep['continuation']!
              as Map<String, Object?>)['tool_results']!
          as List<Object?>),
      <String, Object?>{
        'tool_call': previousStep['tool_call'],
        'tool_response': toolResponse,
      },
    ];
    final continuation = previousStep['continuation']! as Map<String, Object?>;
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

class _FallbackReader implements ReviewDueReader {
  _FallbackReader(this.result);

  final ReviewDueSnapshot result;
  var calls = 0;

  @override
  Future<ReviewDueSnapshot> read(AgentContext ctx) async {
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
