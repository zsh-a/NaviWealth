import 'package:naviwealth/app/agent_runtime/bridges/agent_runtime_native_bridge.dart';
import 'package:naviwealth/app/agent_runtime/catalog/agent_runtime_catalog.dart';
import 'package:naviwealth/app/agent_runtime/runner/agent_runtime_step_runner.dart';
import 'package:naviwealth/app/agent_runtime/tools/agent_runtime_tool_host.dart';
import 'package:naviwealth/app/agent_runtime/trace/agent_runtime_trace_recorder.dart';
import 'package:naviwealth/core/ai/runtime/agent_runtime/agent_runtime_effect_plan_binding.dart';
import 'package:naviwealth/core/ai/runtime/device/device_tool_dispatcher.dart';

import 'agent_runtime_native_bridge_test_harness.dart';

AgentRuntimeEffectPlanBinding agentRuntimeEffectPlanTestBinding({
  required String agentId,
  required String domain,
  required String surface,
  required AgentRuntimeNativeBridge bridge,
  required DeviceToolDispatcher dispatcher,
  required AgentRuntimeCatalog catalog,
  AgentRuntimeStepTraceRecorder? recordTrace,
}) {
  return AgentRuntimeEffectPlanBinding(
    agentId: agentId,
    domain: domain,
    surface: surface,
    stepRunner: AgentRuntimeNativeStepRunner(
      bridge: bridge,
      toolHost: AgentRuntimeToolHost(dispatcher: dispatcher),
    ),
    catalogJson: catalog.toJson(),
    recordTrace: recordTrace,
  );
}

class FakeAgentRuntimeEffectPlanBridge extends FakeAgentRuntimeNativeBridge {
  final startRequests = <AgentRuntimeEffectPlanStartRequest>[];
  var _plan = const <Object?>[];
  var _next = 0;
  final _responses = <Map<String, Object?>>[];

  @override
  Future<Map<String, Object?>> startRunStep({
    required Map<String, Object?> catalog,
    required Map<String, Object?> request,
    required String agentId,
  }) async {
    startRequests.add(
      AgentRuntimeEffectPlanStartRequest(request: request, agentId: agentId),
    );
    final input = request['input']! as Map<String, Object?>;
    _plan = input['effects']! as List<Object?>;
    _next = 0;
    _responses.clear();
    return _toolCallStep(agentId);
  }

  @override
  Future<Map<String, Object?>> continueRunStep({
    required Map<String, Object?> catalog,
    required Map<String, Object?> previousStep,
    required Map<String, Object?> effectResponse,
    required String agentId,
  }) async {
    _responses.add(<String, Object?>{
      'effect': previousStep['effect'],
      'effect_response': effectResponse,
    });
    _next += 1;
    if (_next < _plan.length) return _toolCallStep(agentId);

    final effectResults = _effectResults();
    return <String, Object?>{
      'protocol_version': 'agent.v1',
      'run_id': previousStep['run_id'],
      'agent_id': agentId,
      'status': 'completed',
      'output': <String, Object?>{
        'mode': effectResults.length > 1
            ? 'frb_effect_loop'
            : 'frb_effect_step',
        'effect': previousStep['effect'],
        'effect_result': effectResponse['result'],
        'effect_response': effectResponse,
        'effect_results': effectResults,
      },
    };
  }

  Map<String, Object?> _toolCallStep(String agentId) {
    final item = _plan[_next]! as Map<String, Object?>;
    final remaining = _plan.skip(_next + 1).toList(growable: false);
    final step = <String, Object?>{
      'protocol_version': 'agent.v1',
      'run_id': 'run_1',
      'agent_id': agentId,
      'status': 'effect_requested',
      'effect': <String, Object?>{
        'kind': 'tool',
        'effect_id': 'call_${_next + 1}',
        'name': item['name'],
        'input': item['input'],
      },
    };
    if (remaining.isNotEmpty || _responses.isNotEmpty) {
      step['continuation'] = <String, Object?>{
        'next_step_index': _next + 1,
        'effects': remaining,
        'effect_results': _effectResults(),
      };
    }
    return step;
  }

  List<Map<String, Object?>> _effectResults() {
    return _responses
        .map(
          (response) => <String, Object?>{
            'effect': response['effect'],
            'effect_response': response['effect_response'],
          },
        )
        .toList(growable: false);
  }
}

class FailingAgentRuntimeEffectPlanBridge
    extends FakeAgentRuntimeEffectPlanBridge {
  @override
  Future<Map<String, Object?>> startRunStep({
    required Map<String, Object?> catalog,
    required Map<String, Object?> request,
    required String agentId,
  }) async {
    throw StateError('native unavailable');
  }
}

class AgentRuntimeEffectPlanStartRequest {
  const AgentRuntimeEffectPlanStartRequest({
    required this.request,
    required this.agentId,
  });

  final Map<String, Object?> request;
  final String agentId;
}

class AgentRuntimeEffectPlanToolEffect {
  const AgentRuntimeEffectPlanToolEffect(this.name, this.input);

  final String name;
  final Object? input;
}
