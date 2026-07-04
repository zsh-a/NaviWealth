library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naviwealth/app/agent_runtime/bridges/agent_runtime_native_bridge.dart';
import 'package:naviwealth/app/agent_runtime/tools/agent_runtime_tool_dispatcher.dart';
import 'package:naviwealth/app/agent_runtime/tools/agent_runtime_tool_host.dart';
import 'package:naviwealth/core/ai/runtime/agent_runtime/agent_runtime_effect_plan_binding.dart';
import 'package:naviwealth/core/ai/runtime/agent_runtime/agent_runtime_json.dart';
import 'package:naviwealth/core/ai/runtime/agent_runtime/agent_runtime_protocol.dart';

export 'package:naviwealth/core/ai/runtime/agent_runtime/agent_runtime_step_result.dart'
    show AgentRuntimeNativeStepRunResult;

final agentRuntimeNativeStepRunnerProvider =
    Provider<AgentRuntimeNativeStepRunner>((ref) {
      return AgentRuntimeNativeStepRunner(
        bridge: ref.watch(agentRuntimeNativeBridgeProvider),
        toolHost: ref.watch(agentRuntimeToolHostProvider),
      );
    });

class AgentRuntimeNativeStepRunner implements AgentRuntimeEffectStepRunner {
  AgentRuntimeNativeStepRunner({
    required AgentRuntimeNativeBridge bridge,
    required AgentRuntimeToolHost toolHost,
    int defaultMaxEffectSteps = 4,
  }) : _bridge = bridge,
       _toolDispatcher = AgentRuntimeToolDispatcher(
         handler: toolHost.handleLine,
       ),
       _defaultMaxEffectSteps = defaultMaxEffectSteps;

  final AgentRuntimeNativeBridge _bridge;
  final AgentRuntimeToolDispatcher _toolDispatcher;
  final int _defaultMaxEffectSteps;

  AgentRuntimeNativeBridge get bridge => _bridge;

  Future<Map<String, Object?>> startAndDispatchFirstEffectStep({
    required Map<String, Object?> catalog,
    required Map<String, Object?> request,
    required String agentId,
  }) {
    return runUntilTerminal(
      catalog: catalog,
      request: request,
      agentId: agentId,
      maxEffectSteps: 1,
    );
  }

  Future<Map<String, Object?>> runUntilTerminal({
    required Map<String, Object?> catalog,
    required Map<String, Object?> request,
    required String agentId,
    int? maxEffectSteps,
  }) async {
    return (await runUntilTerminalWithTrace(
      catalog: catalog,
      request: request,
      agentId: agentId,
      maxEffectSteps: maxEffectSteps,
    )).terminalStep;
  }

  @override
  Future<AgentRuntimeNativeStepRunResult> runUntilTerminalWithTrace({
    required Map<String, Object?> catalog,
    required Map<String, Object?> request,
    required String agentId,
    int? maxEffectSteps,
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
      maxEffectSteps: maxEffectSteps,
    );
  }

  Future<Map<String, Object?>> continueUntilTerminal({
    required Map<String, Object?> catalog,
    required Map<String, Object?> initialStep,
    required String agentId,
    int? maxEffectSteps,
  }) async {
    return (await continueUntilTerminalWithTrace(
      catalog: catalog,
      initialStep: initialStep,
      agentId: agentId,
      maxEffectSteps: maxEffectSteps,
    )).terminalStep;
  }

  Future<AgentRuntimeNativeStepRunResult> continueUntilTerminalWithTrace({
    required Map<String, Object?> catalog,
    required Map<String, Object?> initialStep,
    required String agentId,
    int? maxEffectSteps,
  }) async {
    final limit = maxEffectSteps ?? _defaultMaxEffectSteps;
    if (limit < 0) {
      throw RangeError.value(limit, 'maxEffectSteps', 'must be non-negative');
    }

    var step = initialStep;
    var dispatched = 0;
    final steps = <Map<String, Object?>>[step];
    final effectResponses = <Map<String, Object?>>[];
    var budgetExhausted = false;

    while (_isHostEffectRequested(step)) {
      if (dispatched >= limit) {
        step = await _bridge.continueRunStep(
          catalog: catalog,
          previousStep: step,
          effectResponse: agentRuntimeEffectBudgetExhaustedResponse(
            maxEffectSteps: limit,
            dispatchedEffectCount: dispatched,
          ),
          agentId: agentId,
        );
        steps.add(step);
        budgetExhausted = true;
        return AgentRuntimeNativeStepRunResult(
          terminalStep: step,
          steps: steps,
          effectResponses: effectResponses,
          nativeTraceEvents: _nativeTraceEvents(steps),
          dispatchedEffectCount: dispatched,
          budgetExhausted: budgetExhausted,
        );
      }
      dispatched += 1;

      final response = await _dispatchHostEffect(
        step: step,
        catalog: catalog,
        maxEffectSteps: maxEffectSteps,
      );
      effectResponses.add(response);
      step = await _bridge.continueRunStep(
        catalog: catalog,
        previousStep: step,
        effectResponse: response,
        agentId: agentId,
      );
      steps.add(step);
    }

    return AgentRuntimeNativeStepRunResult(
      terminalStep: step,
      steps: steps,
      effectResponses: effectResponses,
      nativeTraceEvents: _nativeTraceEvents(steps),
      dispatchedEffectCount: dispatched,
      budgetExhausted: budgetExhausted,
    );
  }

  Future<Map<String, Object?>> _dispatchToolCall(
    Map<String, Object?> step,
  ) async {
    final effect = agentRuntimeObject(
      step['effect'],
      label: 'native agent-runtime effect',
    );
    final name = effect['name'];
    if (name is! String || name.isEmpty) {
      throw const FormatException('native effect.name is required');
    }

    return (await _toolDispatcher.call(
      AgentRuntimeToolCall(
        id: _effectId(effect, step),
        name: name,
        input: effect['input'],
      ),
    )).response;
  }

  Future<Map<String, Object?>> _dispatchHostEffect({
    required Map<String, Object?> step,
    required Map<String, Object?> catalog,
    int? maxEffectSteps,
  }) async {
    if (step['status'] != 'effect_requested') {
      throw FormatException(
        'native agent-runtime host effect status is unsupported',
        step['status'],
      );
    }
    final effect = agentRuntimeObject(
      step['effect'],
      label: 'native agent-runtime effect',
    );
    return switch (effect['kind']) {
      'tool' => _dispatchToolCall(step),
      'subagent' => _dispatchSubagent(
        step: step,
        catalog: catalog,
        maxEffectSteps: maxEffectSteps,
      ),
      _ => throw FormatException(
        'native agent-runtime effect kind is unsupported',
        effect['kind'],
      ),
    };
  }

  Future<Map<String, Object?>> _dispatchSubagent({
    required Map<String, Object?> step,
    required Map<String, Object?> catalog,
    int? maxEffectSteps,
  }) async {
    final subagentCall = agentRuntimeObject(
      step['effect'],
      label: 'native agent-runtime effect',
    );
    final subagentId = agentRuntimeString(subagentCall['agent_id']);
    if (subagentId.isEmpty) {
      throw const FormatException('native effect.agent_id is required');
    }
    final id = _effectId(subagentCall, step);
    try {
      final childRun = await runUntilTerminalWithTrace(
        catalog: catalog,
        request: _subagentRunRequest(subagentCall),
        agentId: subagentId,
        maxEffectSteps: maxEffectSteps,
      );
      return <String, Object?>{
        'jsonrpc': '2.0',
        'id': id,
        'result': <String, Object?>{
          'agent_id': subagentId,
          'terminal_step': childRun.terminalStep,
          'steps': childRun.steps,
          'effect_responses': childRun.effectResponses,
          'native_trace_events': childRun.nativeTraceEvents,
          'dispatched_effect_count': childRun.dispatchedEffectCount,
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
    'effect_requested' => true,
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

Object _effectId(Map<String, Object?> effect, Map<String, Object?> step) {
  final explicitId = effect['effect_id'];
  if (explicitId is String && explicitId.isNotEmpty) return explicitId;
  final runId = step['run_id'];
  if (runId is String && runId.isNotEmpty) return runId;
  return 'effect';
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
