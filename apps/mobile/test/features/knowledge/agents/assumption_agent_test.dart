import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/app/agent_runtime/bridges/agent_runtime_native_bridge.dart';
import 'package:naviwealth/app/agent_runtime/catalog/agent_runtime_catalog.dart';
import 'package:naviwealth/core/ai/agents/agent.dart';
import 'package:naviwealth/core/ai/runtime/agent_runtime/agent_runtime_effect_plan_binding.dart';
import 'package:naviwealth/core/ai/runtime/device/device_tool_dispatcher.dart';
import 'package:naviwealth/core/ai/runtime/device/device_tool_session.dart';
import 'package:naviwealth/features/knowledge/agents/assumption_agent.dart';

import '../../../app/agent_runtime_effect_plan_test_harness.dart';

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
      'reads assumptions through FRB list_open_assumptions effect loop',
      () async {
        final dispatcher = _AssumptionDispatcher();
        final bridge = FakeAgentRuntimeEffectPlanBridge();
        final traces = <AgentRuntimeNativeStepRunResult>[];
        final reader = FrbAssumptionReviewReader(
          runtime: _runtime(
            bridge: bridge,
            dispatcher: dispatcher,
            recordTrace: (stepRun) async => traces.add(stepRun),
          ),
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
        expect(traces.single.dispatchedEffectCount, 1);
      },
    );

    test('falls back when FRB effect path fails', () async {
      final fallback = _FallbackReader(const <AssumptionReviewItem>[
        AssumptionReviewItem(
          id: 'fallback_assumption',
          statement: 'Fallback assumption',
          daysSinceVerify: 100,
        ),
      ]);
      final reader = FrbAssumptionReviewReader(
        runtime: _runtime(
          bridge: FailingAgentRuntimeEffectPlanBridge(),
          dispatcher: _AssumptionDispatcher(),
        ),
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
          runtime: _runtime(
            bridge: FakeAgentRuntimeEffectPlanBridge(),
            dispatcher: _AssumptionDispatcher(),
            recordTrace: (_) async =>
                throw StateError('trace store unavailable'),
          ),
          fallback: fallback,
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

AgentRuntimeEffectPlanBinding _runtime({
  required AgentRuntimeNativeBridge bridge,
  required DeviceToolDispatcher dispatcher,
  Future<void> Function(AgentRuntimeNativeStepRunResult stepRun)? recordTrace,
}) {
  return agentRuntimeEffectPlanTestBinding(
    agentId: kKnowledgeAssumptionAgentId,
    domain: 'knowledge',
    surface: 'knowledge_assumption',
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
  final calls = <AgentRuntimeEffectPlanToolEffect>[];

  @override
  Future<Object?> dispatch(
    DeviceToolSession session,
    String name,
    Object? input,
  ) async {
    calls.add(AgentRuntimeEffectPlanToolEffect(name, input));
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
