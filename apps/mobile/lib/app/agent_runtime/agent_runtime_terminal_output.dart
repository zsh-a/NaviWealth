/// Shared parsing helpers for native agent-runtime terminal step output.
library;

import 'agent_runtime_json.dart';

Map<String, Object?>? agentRuntimeTerminalOutput(Map<String, Object?> step) {
  return agentRuntimeObjectOrNull(step['output']);
}

Map<String, Map<String, Object?>> agentRuntimeTerminalToolResultsByName(
  Map<String, Object?> step,
) {
  final output = agentRuntimeTerminalOutput(step);
  if (output == null) return const <String, Map<String, Object?>>{};
  return agentRuntimeToolResultsByName(output);
}

Map<String, Object?>? agentRuntimeTerminalToolResult(
  Map<String, Object?> step,
  String toolName,
) {
  final output = agentRuntimeTerminalOutput(step);
  if (output == null) return null;
  return agentRuntimeToolResultsByName(output)[toolName] ??
      agentRuntimeObjectOrNull(output['tool_result']);
}

Map<String, Map<String, Object?>> agentRuntimeToolResultsByName(
  Map<String, Object?> output,
) {
  final byTool = <String, Map<String, Object?>>{};
  final toolResults = output['tool_results'];
  if (toolResults is List) {
    for (final raw in toolResults) {
      final item = agentRuntimeObjectOrNull(raw);
      final call = agentRuntimeObjectOrNull(item?['tool_call']);
      final response = agentRuntimeObjectOrNull(item?['tool_response']);
      final name = call?['name'];
      final result = agentRuntimeObjectOrNull(response?['result']);
      if (name is String && result != null) byTool[name] = result;
    }
  }

  final singleCall = agentRuntimeObjectOrNull(output['tool_call']);
  final singleName = singleCall?['name'];
  final singleResult = agentRuntimeObjectOrNull(output['tool_result']);
  if (singleName is String && singleResult != null) {
    byTool.putIfAbsent(singleName, () => singleResult);
  }
  return byTool;
}
