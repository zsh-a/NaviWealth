/// Shared parsing helpers for native agent-runtime terminal step output.
library;

import 'agent_runtime_json.dart';

Map<String, Object?>? agentRuntimeTerminalOutput(Map<String, Object?> step) {
  return agentRuntimeObjectOrNull(step['output']);
}

Map<String, Map<String, Object?>> agentRuntimeTerminalEffectResultsByToolName(
  Map<String, Object?> step,
) {
  final output = agentRuntimeTerminalOutput(step);
  if (output == null) return const <String, Map<String, Object?>>{};
  return agentRuntimeEffectResultsByToolName(output);
}

Map<String, Object?>? agentRuntimeTerminalEffectResultForTool(
  Map<String, Object?> step,
  String toolName,
) {
  final output = agentRuntimeTerminalOutput(step);
  if (output == null) return null;
  return agentRuntimeEffectResultsByToolName(output)[toolName];
}

Map<String, Map<String, Object?>> agentRuntimeEffectResultsByToolName(
  Map<String, Object?> output,
) {
  final byTool = <String, Map<String, Object?>>{};
  final effectResults = output['effect_results'];
  if (effectResults is List) {
    for (final raw in effectResults) {
      final item = agentRuntimeObjectOrNull(raw);
      final effect = agentRuntimeObjectOrNull(item?['effect']);
      if (effect?['kind'] != 'tool') continue;
      final response = agentRuntimeObjectOrNull(item?['effect_response']);
      final name = effect?['name'];
      final result = agentRuntimeObjectOrNull(response?['result']);
      if (name is String && result != null) byTool[name] = result;
    }
  }

  final singleEffect = agentRuntimeObjectOrNull(output['effect']);
  if (singleEffect != null && singleEffect['kind'] == 'tool') {
    final singleName = singleEffect['name'];
    final singleResult = agentRuntimeObjectOrNull(output['effect_result']);
    if (singleName is String && singleResult != null) {
      byTool.putIfAbsent(singleName, () => singleResult);
    }
  }
  return byTool;
}
