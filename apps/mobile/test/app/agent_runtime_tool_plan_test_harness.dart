import 'package:naviwealth/app/agent_runtime/agent_runtime_catalog.dart';
import 'package:naviwealth/app/agent_runtime/agent_runtime_native_bridge.dart';
import 'package:naviwealth/app/agent_runtime/agent_runtime_step_runner.dart';
import 'package:naviwealth/app/agent_runtime/agent_runtime_tool_host.dart';
import 'package:naviwealth/app/agent_runtime/agent_runtime_tool_plan_binding.dart';
import 'package:naviwealth/app/agent_runtime/agent_runtime_trace_recorder.dart';
import 'package:naviwealth/core/ai/runtime/device/device_tool_dispatcher.dart';

import 'agent_runtime_native_bridge_test_harness.dart';

AgentRuntimeToolPlanBinding agentRuntimeToolPlanTestBinding({
  required String agentId,
  required String domain,
  required String surface,
  required AgentRuntimeNativeBridge bridge,
  required DeviceToolDispatcher dispatcher,
  required AgentRuntimeCatalog catalog,
  AgentRuntimeStepTraceRecorder? recordTrace,
}) {
  return AgentRuntimeToolPlanBinding(
    agentId: agentId,
    domain: domain,
    surface: surface,
    stepRunner: AgentRuntimeNativeStepRunner(
      bridge: bridge,
      toolHost: AgentRuntimeToolHost(dispatcher: dispatcher),
    ),
    catalog: catalog,
    recordTrace: recordTrace,
  );
}

class FakeAgentRuntimeToolPlanBridge extends FakeAgentRuntimeNativeBridge {
  final startRequests = <AgentRuntimeToolPlanStartRequest>[];
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
      AgentRuntimeToolPlanStartRequest(request: request, agentId: agentId),
    );
    final input = request['input']! as Map<String, Object?>;
    _plan = input['tool_plan']! as List<Object?>;
    _next = 0;
    _responses.clear();
    return _toolCallStep(agentId);
  }

  @override
  Future<Map<String, Object?>> continueRunStep({
    required Map<String, Object?> catalog,
    required Map<String, Object?> previousStep,
    required Map<String, Object?> toolResponse,
    required String agentId,
  }) async {
    _responses.add(<String, Object?>{
      'tool_call': previousStep['tool_call'],
      'tool_response': toolResponse,
    });
    _next += 1;
    if (_next < _plan.length) return _toolCallStep(agentId);

    final toolResults = _toolResults();
    return <String, Object?>{
      'protocol_version': 'agent.v1',
      'run_id': previousStep['run_id'],
      'agent_id': agentId,
      'status': 'completed',
      'output': <String, Object?>{
        'mode': toolResults.length > 1 ? 'frb_tool_loop' : 'frb_tool_step',
        'tool_call': previousStep['tool_call'],
        'tool_result': toolResponse['result'],
        'tool_response': toolResponse,
        'tool_results': toolResults,
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
      'status': 'tool_call_requested',
      'tool_call': <String, Object?>{
        'tool_call_id': 'call_${_next + 1}',
        'name': item['name'],
        'input': item['input'],
      },
    };
    if (remaining.isNotEmpty || _responses.isNotEmpty) {
      step['continuation'] = <String, Object?>{
        'next_step_index': _next + 1,
        'tool_plan': remaining,
        'tool_results': _toolResults(),
      };
    }
    return step;
  }

  List<Map<String, Object?>> _toolResults() {
    return _responses
        .map(
          (response) => <String, Object?>{
            'tool_call': response['tool_call'],
            'tool_response': response['tool_response'],
          },
        )
        .toList(growable: false);
  }
}

class FailingAgentRuntimeToolPlanBridge extends FakeAgentRuntimeToolPlanBridge {
  @override
  Future<Map<String, Object?>> startRunStep({
    required Map<String, Object?> catalog,
    required Map<String, Object?> request,
    required String agentId,
  }) async {
    throw StateError('native unavailable');
  }
}

class AgentRuntimeToolPlanStartRequest {
  const AgentRuntimeToolPlanStartRequest({
    required this.request,
    required this.agentId,
  });

  final Map<String, Object?> request;
  final String agentId;
}

class AgentRuntimeToolPlanToolCall {
  const AgentRuntimeToolPlanToolCall(this.name, this.input);

  final String name;
  final Object? input;
}
