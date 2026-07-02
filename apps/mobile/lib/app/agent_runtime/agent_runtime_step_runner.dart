library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ai/runtime/agent_runtime/agent_runtime_json.dart';
import '../../core/ai/runtime/agent_runtime/agent_runtime_tool_plan_binding.dart';
import 'agent_runtime_native_bridge.dart';
import 'agent_runtime_tool_dispatcher.dart';
import 'agent_runtime_tool_host.dart';

export '../../core/ai/runtime/agent_runtime/agent_runtime_step_result.dart'
    show AgentRuntimeNativeStepRunResult;

final agentRuntimeNativeStepRunnerProvider =
    Provider<AgentRuntimeNativeStepRunner>((ref) {
      return AgentRuntimeNativeStepRunner(
        bridge: ref.watch(agentRuntimeNativeBridgeProvider),
        toolHost: ref.watch(agentRuntimeToolHostProvider),
      );
    });

class AgentRuntimeNativeStepRunner implements AgentRuntimeToolPlanStepRunner {
  AgentRuntimeNativeStepRunner({
    required AgentRuntimeNativeBridge bridge,
    required AgentRuntimeToolHost toolHost,
    int defaultMaxToolSteps = 4,
  }) : _bridge = bridge,
       _toolDispatcher = AgentRuntimeToolDispatcher(
         handler: toolHost.handleLine,
       ),
       _defaultMaxToolSteps = defaultMaxToolSteps;

  final AgentRuntimeNativeBridge _bridge;
  final AgentRuntimeToolDispatcher _toolDispatcher;
  final int _defaultMaxToolSteps;

  AgentRuntimeNativeBridge get bridge => _bridge;

  Future<Map<String, Object?>> startAndDispatchFirstToolStep({
    required Map<String, Object?> catalog,
    required Map<String, Object?> request,
    required String agentId,
  }) {
    return runUntilTerminal(
      catalog: catalog,
      request: request,
      agentId: agentId,
      maxToolSteps: 1,
    );
  }

  Future<Map<String, Object?>> runUntilTerminal({
    required Map<String, Object?> catalog,
    required Map<String, Object?> request,
    required String agentId,
    int? maxToolSteps,
  }) async {
    return (await runUntilTerminalWithTrace(
      catalog: catalog,
      request: request,
      agentId: agentId,
      maxToolSteps: maxToolSteps,
    )).terminalStep;
  }

  @override
  Future<AgentRuntimeNativeStepRunResult> runUntilTerminalWithTrace({
    required Map<String, Object?> catalog,
    required Map<String, Object?> request,
    required String agentId,
    int? maxToolSteps,
  }) async {
    final step = await _bridge.startRunStep(
      catalog: catalog,
      request: request,
      agentId: agentId,
    );
    return continueUntilTerminalWithTrace(
      catalog: catalog,
      initialStep: step,
      agentId: agentId,
      maxToolSteps: maxToolSteps,
    );
  }

  Future<Map<String, Object?>> continueUntilTerminal({
    required Map<String, Object?> catalog,
    required Map<String, Object?> initialStep,
    required String agentId,
    int? maxToolSteps,
  }) async {
    return (await continueUntilTerminalWithTrace(
      catalog: catalog,
      initialStep: initialStep,
      agentId: agentId,
      maxToolSteps: maxToolSteps,
    )).terminalStep;
  }

  Future<AgentRuntimeNativeStepRunResult> continueUntilTerminalWithTrace({
    required Map<String, Object?> catalog,
    required Map<String, Object?> initialStep,
    required String agentId,
    int? maxToolSteps,
  }) async {
    final limit = maxToolSteps ?? _defaultMaxToolSteps;
    if (limit < 0) {
      throw RangeError.value(limit, 'maxToolSteps', 'must be non-negative');
    }

    var step = initialStep;
    var dispatched = 0;
    final steps = <Map<String, Object?>>[step];
    final toolResponses = <Map<String, Object?>>[];
    var budgetExhausted = false;

    while (step['status'] == 'tool_call_requested') {
      if (dispatched >= limit) {
        step = await _bridge.continueRunStep(
          catalog: catalog,
          previousStep: step,
          toolResponse: agentRuntimeToolBudgetExhaustedResponse(
            maxToolSteps: limit,
            dispatchedToolCount: dispatched,
          ),
          agentId: agentId,
        );
        steps.add(step);
        budgetExhausted = true;
        return AgentRuntimeNativeStepRunResult(
          terminalStep: step,
          steps: steps,
          toolResponses: toolResponses,
          nativeTraceEvents: _nativeTraceEvents(steps),
          dispatchedToolCount: dispatched,
          budgetExhausted: budgetExhausted,
        );
      }
      dispatched += 1;

      final response = await _dispatchToolCall(step);
      toolResponses.add(response);
      step = await _bridge.continueRunStep(
        catalog: catalog,
        previousStep: step,
        toolResponse: response,
        agentId: agentId,
      );
      steps.add(step);
    }

    return AgentRuntimeNativeStepRunResult(
      terminalStep: step,
      steps: steps,
      toolResponses: toolResponses,
      nativeTraceEvents: _nativeTraceEvents(steps),
      dispatchedToolCount: dispatched,
      budgetExhausted: budgetExhausted,
    );
  }

  Future<Map<String, Object?>> _dispatchToolCall(
    Map<String, Object?> step,
  ) async {
    final toolCall = agentRuntimeObject(
      step['tool_call'],
      label: 'native agent-runtime tool_call',
    );
    final name = toolCall['name'];
    if (name is! String || name.isEmpty) {
      throw const FormatException('native tool_call.name is required');
    }

    return (await _toolDispatcher.call(
      AgentRuntimeToolCall(
        id: _toolCallId(toolCall, step),
        name: name,
        input: toolCall['input'],
      ),
    )).response;
  }
}

List<Map<String, Object?>> _nativeTraceEvents(
  Iterable<Map<String, Object?>> steps,
) {
  return [
    for (final step in steps) ?agentRuntimeObjectOrNull(step['trace_event']),
  ];
}

Object _toolCallId(Map<String, Object?> toolCall, Map<String, Object?> step) {
  final explicitId = toolCall['tool_call_id'];
  if (explicitId is String && explicitId.isNotEmpty) return explicitId;
  final runId = step['run_id'];
  if (runId is String && runId.isNotEmpty) return runId;
  return 'tool_call';
}
