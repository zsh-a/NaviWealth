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
    this.isError = false,
  });

  final Object id;
  final String name;
  final Map<String, Object?> response;
  final Object? output;
  final bool isError;

  String get stringId => id is String ? id as String : id.toString();

  String? get errorCode {
    if (!isError) return null;
    final object =
        agentRuntimeObjectOrNull(output) ?? const <String, Object?>{};
    final code = agentRuntimeString(object['code']);
    return code.isEmpty ? 'agent_runtime_tool_error' : code;
  }

  Map<String, Object?> toChatToolResult() => <String, Object?>{
    'tool_call_id': stringId,
    'tool_name': name,
    'output': output,
    'is_error': isError,
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
        return AgentRuntimeToolResult(
          id: call.id,
          name: call.name,
          response: response,
          output: error,
          isError: true,
        );
      }
      return AgentRuntimeToolResult(
        id: call.id,
        name: call.name,
        response: response,
        output: response['result'],
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
        isError: true,
      );
    }
  }
}
