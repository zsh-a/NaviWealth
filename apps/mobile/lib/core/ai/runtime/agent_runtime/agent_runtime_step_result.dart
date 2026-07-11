library;

class AgentRuntimeNativeStepRunResult {
  const AgentRuntimeNativeStepRunResult({
    required this.terminalStep,
    this.steps = const <Map<String, Object?>>[],
    this.effectResponses = const <Map<String, Object?>>[],
    this.nativeTraceEvents = const <Map<String, Object?>>[],
    this.dispatchedEffectCount = 0,
    this.budgetExhausted = false,
    this.maxEffectSteps,
    this.remainingEffectSteps,
    this.maxSubagentDepth,
    this.subagentDepthExceeded = false,
    this.traceId,
    this.terminalSnapshot,
  });

  final Map<String, Object?> terminalStep;
  final List<Map<String, Object?>> steps;
  final List<Map<String, Object?>> effectResponses;
  final List<Map<String, Object?>> nativeTraceEvents;
  final int dispatchedEffectCount;
  final bool budgetExhausted;
  final int? maxEffectSteps;
  final int? remainingEffectSteps;
  final int? maxSubagentDepth;
  final bool subagentDepthExceeded;
  final String? traceId;
  final Map<String, Object?>? terminalSnapshot;

  Map<String, Object?> toJson() => <String, Object?>{
    'terminal_step': terminalStep,
    'steps': steps,
    'effect_responses': effectResponses,
    'native_trace_events': nativeTraceEvents,
    'dispatched_effect_count': dispatchedEffectCount,
    'budget_exhausted': budgetExhausted,
    if (maxEffectSteps != null) 'max_effect_steps': maxEffectSteps,
    if (remainingEffectSteps != null)
      'remaining_effect_steps': remainingEffectSteps,
    if (maxSubagentDepth != null) 'max_subagent_depth': maxSubagentDepth,
    'subagent_depth_exceeded': subagentDepthExceeded,
    if (traceId != null) 'trace_id': traceId,
    if (terminalSnapshot != null) 'terminal_snapshot': terminalSnapshot,
  };

  AgentRuntimeNativeStepRunResult withTraceId(String? traceId) {
    if (traceId == null || traceId == this.traceId) return this;
    return AgentRuntimeNativeStepRunResult(
      terminalStep: terminalStep,
      steps: steps,
      effectResponses: effectResponses,
      nativeTraceEvents: nativeTraceEvents,
      dispatchedEffectCount: dispatchedEffectCount,
      budgetExhausted: budgetExhausted,
      maxEffectSteps: maxEffectSteps,
      remainingEffectSteps: remainingEffectSteps,
      maxSubagentDepth: maxSubagentDepth,
      subagentDepthExceeded: subagentDepthExceeded,
      traceId: traceId,
      terminalSnapshot: terminalSnapshot,
    );
  }
}
