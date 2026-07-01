import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/app/agent_runtime/agent_runtime_catalog.dart';
import 'package:naviwealth/app/agent_runtime/agent_runtime_native_bridge.dart';
import 'package:naviwealth/app/agent_runtime/agent_runtime_step_runner.dart';
import 'package:naviwealth/app/agent_runtime/agent_runtime_tool_plan_binding.dart';
import 'package:naviwealth/core/ai/agents/agent.dart';
import 'package:naviwealth/core/ai/runtime/device/device_tool_dispatcher.dart';
import 'package:naviwealth/core/ai/runtime/device/device_tool_session.dart';
import 'package:naviwealth/features/knowledge/agents/assumption_agent.dart';
import 'package:naviwealth/features/knowledge/agents/review_agent.dart';

import '../../../app/agent_runtime_tool_plan_test_harness.dart';

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
      final bridge = FakeAgentRuntimeToolPlanBridge();
      final traces = <AgentRuntimeNativeStepRunResult>[];
      final reader = FrbReviewDueReader(
        runtime: _runtime(
          bridge: bridge,
          dispatcher: dispatcher,
          recordTrace: (stepRun) async => traces.add(stepRun),
        ),
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
        runtime: _runtime(
          bridge: FailingAgentRuntimeToolPlanBridge(),
          dispatcher: _ReviewDispatcher(),
        ),
        fallback: fallback,
      );

      final snapshot = await reader.read(_context());

      expect(snapshot.dueReviews.single.id, 'fallback_decision');
      expect(fallback.calls, 1);
    });

    test(
      'ignores trace recording failures after a successful FRB read',
      () async {
        final fallback = _FallbackReader(
          const ReviewDueSnapshot(
            dueReviews: <ReviewDecisionItem>[
              ReviewDecisionItem(
                id: 'fallback_decision',
                question: 'Fallback?',
              ),
            ],
            staleAssumptions: <ReviewAssumptionItem>[],
          ),
        );
        final reader = FrbReviewDueReader(
          runtime: _runtime(
            bridge: FakeAgentRuntimeToolPlanBridge(),
            dispatcher: _ReviewDispatcher(),
            recordTrace: (_) async =>
                throw StateError('trace store unavailable'),
          ),
          fallback: fallback,
        );

        final snapshot = await reader.read(_context());

        expect(snapshot.dueReviews.single.question, 'Revisit portfolio hedge?');
        expect(snapshot.staleAssumptions.single.statement, 'Rates stay high');
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
    agentId: kKnowledgeReviewAgentId,
    domain: 'knowledge',
    surface: 'knowledge_review',
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
  final calls = <AgentRuntimeToolPlanToolCall>[];

  @override
  Future<Object?> dispatch(
    DeviceToolSession session,
    String name,
    Object? input,
  ) async {
    calls.add(AgentRuntimeToolPlanToolCall(name, input));
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
