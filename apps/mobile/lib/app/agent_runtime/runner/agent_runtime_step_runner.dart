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
    int defaultMaxSubagentDepth = 4,
  }) : _bridge = bridge,
       _toolDispatcher = AgentRuntimeToolDispatcher(
         handler: toolHost.handleLine,
       ),
       _defaultMaxEffectSteps = defaultMaxEffectSteps,
       _defaultMaxSubagentDepth = defaultMaxSubagentDepth;

  final AgentRuntimeNativeBridge _bridge;
  final AgentRuntimeToolDispatcher _toolDispatcher;
  final int _defaultMaxEffectSteps;
  final int _defaultMaxSubagentDepth;

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
    final budget = _EffectRunBudget(limit);
    return _continueUntilTerminalWithTrace(
      catalog: catalog,
      initialStep: initialStep,
      agentId: agentId,
      budget: budget,
      depth: 0,
    );
  }

  Future<AgentRuntimeNativeStepRunResult> _continueUntilTerminalWithTrace({
    required Map<String, Object?> catalog,
    required Map<String, Object?> initialStep,
    required String agentId,
    required _EffectRunBudget budget,
    required int depth,
  }) async {
    var step = initialStep;
    final steps = <Map<String, Object?>>[step];
    final effectResponses = <Map<String, Object?>>[];
    var subagentDepthExceeded = false;

    while (_isHostEffectRequested(step)) {
      if (!budget.canDispatch) {
        budget.markExhausted();
        step = await _bridge.continueRunStep(
          catalog: catalog,
          previousStep: step,
          effectResponse: agentRuntimeEffectBudgetExhaustedResponse(
            maxEffectSteps: budget.max,
            dispatchedEffectCount: budget.dispatched,
          ),
          agentId: agentId,
        );
        steps.add(step);
        return AgentRuntimeNativeStepRunResult(
          terminalStep: step,
          steps: steps,
          effectResponses: effectResponses,
          nativeTraceEvents: _nativeTraceEvents(steps),
          dispatchedEffectCount: budget.dispatched,
          budgetExhausted: true,
          maxEffectSteps: budget.max,
          remainingEffectSteps: budget.remaining,
          maxSubagentDepth: _defaultMaxSubagentDepth,
          subagentDepthExceeded: subagentDepthExceeded,
        );
      }
      budget.markDispatched();

      final dispatch = await _dispatchHostEffect(
        step: step,
        catalog: catalog,
        budget: budget,
        depth: depth,
      );
      subagentDepthExceeded =
          subagentDepthExceeded || dispatch.subagentDepthExceeded;
      final response = dispatch.response;
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
      dispatchedEffectCount: budget.dispatched,
      budgetExhausted: budget.exhausted,
      maxEffectSteps: budget.max,
      remainingEffectSteps: budget.remaining,
      maxSubagentDepth: _defaultMaxSubagentDepth,
      subagentDepthExceeded: subagentDepthExceeded,
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

  Future<_HostEffectDispatch> _dispatchHostEffect({
    required Map<String, Object?> step,
    required Map<String, Object?> catalog,
    required _EffectRunBudget budget,
    required int depth,
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
      'tool' => _dispatchToolCall(
        step,
      ).then((response) => _HostEffectDispatch(response)),
      'subagent' => _dispatchSubagent(
        step: step,
        catalog: catalog,
        budget: budget,
        depth: depth,
      ),
      _ => throw FormatException(
        'native agent-runtime effect kind is unsupported',
        effect['kind'],
      ),
    };
  }

  Future<_HostEffectDispatch> _dispatchSubagent({
    required Map<String, Object?> step,
    required Map<String, Object?> catalog,
    required _EffectRunBudget budget,
    required int depth,
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
    if (depth >= _defaultMaxSubagentDepth) {
      return _HostEffectDispatch(<String, Object?>{
        'jsonrpc': '2.0',
        'id': id,
        'error': <String, Object?>{
          'code': 'subagent_depth_exceeded',
          'message':
              'subagent depth exceeded '
              '($_defaultMaxSubagentDepth)',
        },
      }, subagentDepthExceeded: true);
    }
    try {
      final childRun = await _continueUntilTerminalWithTrace(
        catalog: catalog,
        initialStep: await _bridge.startRunStep(
          catalog: catalog,
          request: _subagentRunRequest(subagentCall),
          agentId: subagentId,
        ),
        agentId: subagentId,
        budget: budget,
        depth: depth + 1,
      );
      return _HostEffectDispatch(<String, Object?>{
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
          'max_effect_steps': childRun.maxEffectSteps,
          'remaining_effect_steps': childRun.remainingEffectSteps,
          'max_subagent_depth': childRun.maxSubagentDepth,
          'subagent_depth_exceeded': childRun.subagentDepthExceeded,
        },
      }, subagentDepthExceeded: childRun.subagentDepthExceeded);
    } catch (error) {
      return _HostEffectDispatch(<String, Object?>{
        'jsonrpc': '2.0',
        'id': id,
        'error': <String, Object?>{
          'code': 'subagent_run_failed',
          'message': error.toString(),
        },
      });
    }
  }
}

class _EffectRunBudget {
  _EffectRunBudget(this.max) : remaining = max;

  final int max;
  int remaining;
  bool exhausted = false;

  int get dispatched => max - remaining;

  bool get canDispatch => remaining > 0;

  void markDispatched() {
    remaining -= 1;
  }

  void markExhausted() {
    exhausted = true;
  }
}

class _HostEffectDispatch {
  const _HostEffectDispatch(
    this.response, {
    this.subagentDepthExceeded = false,
  });

  final Map<String, Object?> response;
  final bool subagentDepthExceeded;
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
