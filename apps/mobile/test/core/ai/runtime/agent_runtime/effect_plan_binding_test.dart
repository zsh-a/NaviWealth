import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/runtime/agent_runtime/agent_runtime_effect_plan_binding.dart';

void main() {
  group('AgentRuntimeEffectPlanBinding', () {
    test('records successful step runs and returns a trace id', () async {
      final recorded = <AgentRuntimeNativeStepRunResult>[];
      final binding = AgentRuntimeEffectPlanBinding(
        agentId: 'knowledge_review',
        domain: 'knowledge',
        surface: 'agent_test',
        stepRunner: const _StaticStepRunner(
          AgentRuntimeNativeStepRunResult(
            terminalStep: <String, Object?>{
              'protocol_version': 'agent.v1',
              'run_id': 'run_42',
              'agent_id': 'knowledge_review',
              'status': 'completed',
              'output': <String, Object?>{'ok': true},
            },
          ),
        ),
        catalogJson: const <String, Object?>{},
        recordTrace: (stepRun) async => recorded.add(stepRun),
      );

      final stepRun = await binding.runEffectPlan(
        effectPlan: const <AgentRuntimeEffect>[
          AgentRuntimeEffect.tool(name: 'knowledge.review_due'),
        ],
      );

      expect(recorded, hasLength(1));
      expect(recorded.single.traceId, isNull);
      expect(stepRun.traceId, 'agent-runtime:knowledge_review:run_42');
      expect(
        stepRun.toJson(),
        containsPair('trace_id', 'agent-runtime:knowledge_review:run_42'),
      );
    });

    test(
      'records failed fallback step runs when native execution throws',
      () async {
        final recorded = <AgentRuntimeNativeStepRunResult>[];
        final binding = AgentRuntimeEffectPlanBinding(
          agentId: 'knowledge_review',
          domain: 'knowledge',
          surface: 'agent_test',
          stepRunner: _ThrowingStepRunner(StateError('native unavailable')),
          catalogJson: const <String, Object?>{},
          recordTrace: (stepRun) async => recorded.add(stepRun),
        );

        final value = await binding.readFromEffectPlan<String>(
          effectPlan: const <AgentRuntimeEffect>[
            AgentRuntimeEffect.tool(name: 'knowledge.review_due'),
          ],
          fallback: () async => 'programmatic fallback',
          decode: (_) => 'native value',
          metadata: const <String, Object?>{'fixture': 'fallback'},
        );

        expect(value, 'programmatic fallback');
        expect(recorded, hasLength(1));
        final fallbackRun = recorded.single;
        expect(fallbackRun.terminalStep['agent_id'], 'knowledge_review');
        expect(fallbackRun.terminalStep['status'], 'failed');
        expect(
          fallbackRun.terminalStep['run_id'],
          isA<String>().having(
            (value) => value,
            'prefix',
            startsWith('fallback:'),
          ),
        );
        final output =
            fallbackRun.terminalStep['output']! as Map<String, Object?>;
        expect(output['fallback_reason'], 'effect_plan_failed');
        expect(output['fallback_error'], contains('native unavailable'));
        expect(output['metadata'], containsPair('fixture', 'fallback'));
        expect(fallbackRun.nativeTraceEvents, hasLength(1));
        expect(
          fallbackRun.nativeTraceEvents.single,
          containsPair('kind', 'agent_runtime_fallback'),
        );
      },
    );
  });
}

class _StaticStepRunner implements AgentRuntimeEffectStepRunner {
  const _StaticStepRunner(this.result);

  final AgentRuntimeNativeStepRunResult result;

  @override
  Future<AgentRuntimeNativeStepRunResult> runUntilTerminalWithTrace({
    required Map<String, Object?> catalog,
    required Map<String, Object?> request,
    required String agentId,
    int? maxEffectSteps,
  }) async {
    return result;
  }
}

class _ThrowingStepRunner implements AgentRuntimeEffectStepRunner {
  const _ThrowingStepRunner(this.error);

  final Object error;

  @override
  Future<AgentRuntimeNativeStepRunResult> runUntilTerminalWithTrace({
    required Map<String, Object?> catalog,
    required Map<String, Object?> request,
    required String agentId,
    int? maxEffectSteps,
  }) async {
    throw error;
  }
}
