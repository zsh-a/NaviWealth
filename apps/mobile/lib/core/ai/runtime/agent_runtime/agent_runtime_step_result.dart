library;

class AgentRuntimeNativeStepRunResult {
  const AgentRuntimeNativeStepRunResult({
    required this.terminalStep,
    this.steps = const <Map<String, Object?>>[],
    this.effectResponses = const <Map<String, Object?>>[],
    this.nativeTraceEvents = const <Map<String, Object?>>[],
    this.dispatchedEffectCount = 0,
    this.budgetExhausted = false,
  });

  final Map<String, Object?> terminalStep;
  final List<Map<String, Object?>> steps;
  final List<Map<String, Object?>> effectResponses;
  final List<Map<String, Object?>> nativeTraceEvents;
  final int dispatchedEffectCount;
  final bool budgetExhausted;

  Map<String, Object?> toJson() => <String, Object?>{
    'terminal_step': terminalStep,
    'steps': steps,
    'effect_responses': effectResponses,
    'native_trace_events': nativeTraceEvents,
    'dispatched_effect_count': dispatchedEffectCount,
    'budget_exhausted': budgetExhausted,
  };
}
