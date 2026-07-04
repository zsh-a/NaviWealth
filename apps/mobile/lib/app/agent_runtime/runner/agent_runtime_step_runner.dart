library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naviwealth/app/agent_runtime/bridges/agent_runtime_native_bridge.dart';
import 'package:naviwealth/app/agent_runtime/tools/agent_runtime_tool_dispatcher.dart';
import 'package:naviwealth/app/agent_runtime/tools/agent_runtime_tool_host.dart';
import 'package:naviwealth/core/ai/runtime/agent_runtime/agent_runtime_json.dart';
import 'package:naviwealth/core/ai/runtime/agent_runtime/agent_runtime_protocol.dart';
import 'package:naviwealth/core/ai/runtime/agent_runtime/agent_runtime_tool_plan_binding.dart';

export 'package:naviwealth/core/ai/runtime/agent_runtime/agent_runtime_step_result.dart'
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

    while (_isHostEffectRequested(step)) {
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

      final response = await _dispatchHostEffect(
        step: step,
        catalog: catalog,
        maxToolSteps: maxToolSteps,
      );
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

  Future<Map<String, Object?>> _dispatchHostEffect({
    required Map<String, Object?> step,
    required Map<String, Object?> catalog,
    int? maxToolSteps,
  }) async {
    return switch (step['status']) {
      'tool_call_requested' => _dispatchToolCall(step),
      'subagent_requested' => _dispatchSubagent(
        step: step,
        catalog: catalog,
        maxToolSteps: maxToolSteps,
      ),
      _ => throw FormatException(
        'native agent-runtime host effect status is unsupported',
        step['status'],
      ),
    };
  }

  Future<Map<String, Object?>> _dispatchSubagent({
    required Map<String, Object?> step,
    required Map<String, Object?> catalog,
    int? maxToolSteps,
  }) async {
    final subagentCall = agentRuntimeObject(
      step['subagent_call'],
      label: 'native agent-runtime subagent_call',
    );
    final subagentId = agentRuntimeString(subagentCall['agent_id']);
    if (subagentId.isEmpty) {
      throw const FormatException('native subagent_call.agent_id is required');
    }
    final id = _subagentCallId(subagentCall, step);
    try {
      final childRun = await runUntilTerminalWithTrace(
        catalog: catalog,
        request: _subagentRunRequest(subagentCall),
        agentId: subagentId,
        maxToolSteps: maxToolSteps,
      );
      return <String, Object?>{
        'jsonrpc': '2.0',
        'id': id,
        'result': <String, Object?>{
          'agent_id': subagentId,
          'terminal_step': childRun.terminalStep,
          'steps': childRun.steps,
          'tool_responses': childRun.toolResponses,
          'native_trace_events': childRun.nativeTraceEvents,
          'dispatched_tool_count': childRun.dispatchedToolCount,
          'budget_exhausted': childRun.budgetExhausted,
        },
      };
    } catch (error) {
      return <String, Object?>{
        'jsonrpc': '2.0',
        'id': id,
        'error': <String, Object?>{
          'code': 'subagent_run_failed',
          'message': error.toString(),
        },
      };
    }
  }
}

bool _isHostEffectRequested(Map<String, Object?> step) {
  return switch (step['status']) {
    'tool_call_requested' || 'subagent_requested' => true,
    _ => false,
  };
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

Object _subagentCallId(
  Map<String, Object?> subagentCall,
  Map<String, Object?> step,
) {
  final explicitId = subagentCall['subagent_call_id'];
  if (explicitId is String && explicitId.isNotEmpty) return explicitId;
  final runId = step['run_id'];
  if (runId is String && runId.isNotEmpty) return runId;
  return 'subagent_call';
}

Map<String, Object?> _subagentRunRequest(Map<String, Object?> subagentCall) {
  final request = <String, Object?>{
    'protocol_version': kAgentRuntimeProtocolVersion,
    if (subagentCall['run_id'] case final String runId when runId.isNotEmpty)
      'run_id': runId,
    'input': _subagentInput(subagentCall['input']),
    'trigger': 'manual',
    'metadata':
        agentRuntimeObjectOrNull(subagentCall['metadata']) ??
        const <String, Object?>{},
  };
  final scope = agentRuntimeObjectOrNull(subagentCall['scope']);
  if (scope != null) request['scope'] = scope;
  final workflow = agentRuntimeObjectOrNull(subagentCall['workflow']);
  if (workflow != null) request['workflow'] = workflow;
  return request;
}

Map<String, Object?> _subagentInput(Object? input) {
  return agentRuntimeObjectOrNull(input) ?? <String, Object?>{'value': input};
}
