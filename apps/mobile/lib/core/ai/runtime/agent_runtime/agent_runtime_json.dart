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

/// Nullable variant of [agentRuntimeInt]: returns `null` unless [value] is a
/// num, so callers can distinguish "field absent" from "field is zero".
int? agentRuntimeIntOrNull(Object? value) {
  if (value is num) return value.toInt();
  return null;
}

/// Parses an ISO-8601 string into a UTC datetime, returning `null` for
/// absent, empty, or unparseable values.
DateTime? agentRuntimeDateTimeOrNull(Object? value) {
  if (value is! String || value.isEmpty) return null;
  return DateTime.tryParse(value)?.toUtc();
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

Map<String, Object?> agentRuntimeEffectBudgetExhaustedResponse({
  required Object effectId,
  required int maxEffectSteps,
  required int dispatchedEffectCount,
}) {
  return <String, Object?>{
    'jsonrpc': '2.0',
    'id': effectId,
    'result': <String, Object?>{
      'error': <String, Object?>{
        'code': 'effect_budget_exhausted',
        'message': 'agent runtime effect budget exhausted',
        'max_effect_steps': maxEffectSteps,
        'dispatched_effect_count': dispatchedEffectCount,
      },
    },
  };
}
