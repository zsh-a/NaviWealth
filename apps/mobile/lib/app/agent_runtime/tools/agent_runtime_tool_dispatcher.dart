library;

import 'package:naviwealth/core/ai/runtime/agent_runtime/agent_runtime_json.dart';

typedef AgentRuntimeToolLineHandler = Future<String> Function(String line);

class AgentRuntimeToolCall {
  const AgentRuntimeToolCall({
    required this.id,
    required this.name,
    this.input,
  });

  final Object id;
  final String name;
  final Object? input;

  String get stringId => id is String ? id as String : id.toString();
}

class AgentRuntimeToolResult {
  const AgentRuntimeToolResult({
    required this.id,
    required this.name,
    required this.response,
    required this.output,
    required this.outcome,
    this.isError = false,
  });

  final Object id;
  final String name;
  final Map<String, Object?> response;
  final Object? output;
  final Map<String, Object?> outcome;
  final bool isError;

  String get stringId => id is String ? id as String : id.toString();

  String? get errorCode {
    if (!isError) return null;
    final outcomeCode = agentRuntimeString(outcome['code']);
    if (outcomeCode.isNotEmpty) return outcomeCode;
    final object =
        agentRuntimeObjectOrNull(output) ?? const <String, Object?>{};
    final nested = agentRuntimeObjectOrNull(object['error']);
    final directCode = agentRuntimeString(object['code']);
    final code = directCode.isNotEmpty
        ? directCode
        : agentRuntimeString(nested?['code']);
    return code.isEmpty ? 'agent_runtime_tool_error' : code;
  }

  Map<String, Object?> toChatToolResult() => <String, Object?>{
    'tool_call_id': stringId,
    'tool_name': name,
    'output': output,
    'is_error': isError,
    'outcome': outcome,
  };
}

class AgentRuntimeToolDispatcher {
  const AgentRuntimeToolDispatcher({
    required AgentRuntimeToolLineHandler handler,
  }) : _handler = handler;

  final AgentRuntimeToolLineHandler _handler;

  Future<AgentRuntimeToolResult> call(AgentRuntimeToolCall call) async {
    try {
      final response = agentRuntimeDecodeObject(
        await _handler(
          agentRuntimeEncodeToolCallLine(
            id: call.id,
            name: call.name,
            input: call.input,
          ),
        ),
        label: 'agent-runtime tool response',
      );
      final error = response['error'];
      if (error != null) {
        final outcome = _responseOutcome(
          response,
          fallbackOutput: error,
          transportError: true,
        );
        return AgentRuntimeToolResult(
          id: call.id,
          name: call.name,
          response: response,
          output: error,
          outcome: outcome,
          isError: outcome['status'] != 'ok',
        );
      }
      final output = response['result'];
      final outcome = _responseOutcome(
        response,
        fallbackOutput: output,
        transportError: false,
      );
      return AgentRuntimeToolResult(
        id: call.id,
        name: call.name,
        response: response,
        output: output,
        outcome: outcome,
        isError: outcome['status'] != 'ok',
      );
    } catch (error) {
      final output = <String, Object?>{
        'code': 'agent_runtime_tool_dispatch_failed',
        'message': error.toString(),
      };
      return AgentRuntimeToolResult(
        id: call.id,
        name: call.name,
        response: <String, Object?>{
          'jsonrpc': '2.0',
          'id': call.id,
          'error': output,
        },
        output: output,
        outcome: _inferOutcome(output, transportError: true),
        isError: true,
      );
    }
  }
}

Map<String, Object?> _responseOutcome(
  Map<String, Object?> response, {
  required Object? fallbackOutput,
  required bool transportError,
}) {
  final explicit = agentRuntimeObjectOrNull(response['outcome']);
  return explicit == null
      ? _inferOutcome(fallbackOutput, transportError: transportError)
      : Map<String, Object?>.from(explicit);
}

Map<String, Object?> _inferOutcome(
  Object? output, {
  required bool transportError,
}) {
  final object = agentRuntimeObjectOrNull(output) ?? const <String, Object?>{};
  final nested = object['error'];
  final nestedObject = agentRuntimeObjectOrNull(nested);
  final code = _firstNonEmpty(<Object?>[object['code'], nestedObject?['code']]);
  final message = _firstNonEmpty(<Object?>[
    object['message'],
    nestedObject?['message'],
    if (nested is String) nested,
  ]);
  final hasError =
      transportError || nested != null || object['policy_denied'] == true;
  final status = switch (code) {
    'policy_denied' || 'runtime_not_allowed' => 'policy_denied',
    'approval_required' || 'confirmation_required' => 'approval_required',
    'user_cancel' || 'user_cancelled' || 'cancelled' => 'cancelled',
    _ when hasError => 'error',
    _ => 'ok',
  };
  final outcome = <String, Object?>{
    'status': status,
    'retryable': object['retryable'] == true || code == 'tool_timeout',
    'details':
        agentRuntimeObjectOrNull(object['details']) ??
        const <String, Object?>{},
  };
  if (status != 'ok' && code != null) outcome['code'] = code;
  if (status != 'ok' && message != null) outcome['message'] = message;
  return outcome;
}

String? _firstNonEmpty(Iterable<Object?> values) {
  for (final value in values) {
    if (value is String && value.isNotEmpty) return value;
  }
  return null;
}
