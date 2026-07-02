library;

import 'dart:convert';

Map<String, Object?> agentRuntimeDecodeObject(
  String json, {
  String label = 'agent-runtime JSON',
}) {
  return agentRuntimeObject(jsonDecode(json), label: label);
}

Map<String, Object?> agentRuntimeObject(
  Object? value, {
  String label = 'agent-runtime value',
}) {
  final object = agentRuntimeObjectOrNull(value);
  if (object == null) {
    throw FormatException('$label is not an object');
  }
  return object;
}

Map<String, Object?>? agentRuntimeObjectOrNull(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return null;
}

String agentRuntimeString(Object? value) => value is String ? value : '';

int agentRuntimeInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return 0;
}

String agentRuntimeEncodeToolCallLine({
  required Object id,
  required String name,
  Object? input,
}) {
  return jsonEncode(<String, Object?>{
    'jsonrpc': '2.0',
    'id': id,
    'method': 'tool.call',
    'params': <String, Object?>{
      'name': name,
      'input': input ?? const <String, Object?>{},
    },
  });
}

Map<String, Object?> agentRuntimeToolBudgetExhaustedResponse({
  required int maxToolSteps,
  required int dispatchedToolCount,
}) {
  return <String, Object?>{
    'error': <String, Object?>{
      'code': 'tool_call_budget_exhausted',
      'message': 'agent runtime tool-call budget exhausted',
      'max_tool_steps': maxToolSteps,
      'dispatched_tool_count': dispatchedToolCount,
    },
  };
}
