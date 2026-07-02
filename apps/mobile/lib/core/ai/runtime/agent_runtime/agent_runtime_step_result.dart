library;

class AgentRuntimeNativeStepRunResult {
  const AgentRuntimeNativeStepRunResult({
    required this.terminalStep,
    this.steps = const <Map<String, Object?>>[],
    this.toolResponses = const <Map<String, Object?>>[],
    this.nativeTraceEvents = const <Map<String, Object?>>[],
    this.dispatchedToolCount = 0,
    this.budgetExhausted = false,
  });

  final Map<String, Object?> terminalStep;
  final List<Map<String, Object?>> steps;
  final List<Map<String, Object?>> toolResponses;
  final List<Map<String, Object?>> nativeTraceEvents;
  final int dispatchedToolCount;
  final bool budgetExhausted;

  Map<String, Object?> toJson() => <String, Object?>{
    'terminal_step': terminalStep,
    'steps': steps,
    'tool_responses': toolResponses,
    'native_trace_events': nativeTraceEvents,
    'dispatched_tool_count': dispatchedToolCount,
    'budget_exhausted': budgetExhausted,
  };
}
