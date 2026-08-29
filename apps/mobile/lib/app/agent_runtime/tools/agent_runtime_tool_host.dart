/// JSONL tool-host adapter for the Rust agent runtime.
///
/// The Rust side sends JSON-RPC-style `tool.call` requests over a process or
/// stdio bridge. This adapter maps that protocol to the existing
/// [DeviceToolDispatcher], so Flutter can expose the same device tools used by
/// chat without changing the tool implementations or constructing a legacy
/// provider-specific chat session.
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:naviwealth/core/ai/composition/device_tools_provider.dart';
import 'package:naviwealth/core/ai/runtime/device/device_tool_dispatcher.dart';
import 'package:naviwealth/core/ai/runtime/device/device_tool_session.dart';
import 'package:naviwealth/core/ai/runtime/device/tools/device_tool_registry.dart';

typedef AgentRuntimeSessionFactory = DeviceToolSession Function();

final agentRuntimeToolHostProvider = Provider<AgentRuntimeToolHost>((ref) {
  final registry = DeviceToolRegistry(ref.watch(deviceToolsProvider));
  return AgentRuntimeToolHost(
    dispatcher: DriftDeviceToolDispatcher(ref: ref, registry: registry),
  );
});

/// Assistant-only host with the same policy enforcement but a smaller,
/// route-aware registry. Hallucinated internal tool names therefore fail the
/// allow-list even though scheduled agents can still use them through
/// [agentRuntimeToolHostProvider].
final assistantRuntimeToolHostProvider = Provider<AgentRuntimeToolHost>((ref) {
  final registry = DeviceToolRegistry(ref.watch(assistantDeviceToolsProvider));
  return AgentRuntimeToolHost(
    dispatcher: DriftDeviceToolDispatcher(ref: ref, registry: registry),
  );
});

class AgentRuntimeToolHost {
  AgentRuntimeToolHost({
    required DeviceToolDispatcher dispatcher,
    AgentRuntimeSessionFactory? sessionFactory,
  }) : _dispatcher = dispatcher,
       _sessionFactory = sessionFactory ?? (() => const DeviceToolSession());

  final DeviceToolDispatcher _dispatcher;
  final AgentRuntimeSessionFactory _sessionFactory;

  Future<String> handleLine(String line) async {
    final trimmed = line.trim();
    if (trimmed.isEmpty) {
      return _encode(_error(null, -32600, 'empty request'));
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(trimmed);
    } catch (e) {
      return _encode(_error(null, -32700, 'parse error: $e'));
    }
    if (decoded is! Map<String, Object?>) {
      return _encode(_error(null, -32600, 'request must be a JSON object'));
    }

    final id = decoded['id'];
    final jsonrpc = decoded['jsonrpc'];
    if (jsonrpc != null && jsonrpc != '2.0') {
      return _encode(_error(id, -32600, 'invalid jsonrpc version'));
    }
    if (decoded['method'] != 'tool.call') {
      return _encode(_error(id, -32601, 'method not found'));
    }

    final params = decoded['params'];
    if (params is! Map<String, Object?>) {
      return _encode(_error(id, -32602, 'params must be an object'));
    }
    final name = params['name'];
    if (name is! String || name.isEmpty) {
      return _encode(_error(id, -32602, 'params.name is required'));
    }

    try {
      final result = await _dispatcher.dispatch(
        _sessionFactory(),
        name,
        params['input'] ?? const <String, Object?>{},
      );
      return _encode(_result(id, result, outcome: _inferOutcome(result)));
    } catch (e) {
      return _encode(_error(id, -32000, 'tool host error: $e'));
    }
  }
}

Future<void> runAgentRuntimeToolHostLines({
  required AgentRuntimeToolHost host,
  required Stream<String> input,
  required void Function(String line) output,
}) async {
  await for (final line in input) {
    output(await host.handleLine(line));
  }
}

String _encode(Map<String, Object?> value) => jsonEncode(value);

Map<String, Object?> _result(
  Object? id,
  Object? result, {
  required Map<String, Object?> outcome,
}) {
  final response = <String, Object?>{
    'jsonrpc': '2.0',
    'result': result,
    'outcome': outcome,
  };
  if (id != null) response['id'] = id;
  return response;
}

Map<String, Object?> _inferOutcome(Object? output) {
  final object = output is Map
      ? output.map((key, value) => MapEntry(key.toString(), value))
      : const <String, Object?>{};
  final nested = object['error'];
  final nestedObject = nested is Map
      ? nested.map((key, value) => MapEntry(key.toString(), value))
      : const <String, Object?>{};
  final code =
      _nonEmptyString(object['code']) ?? _nonEmptyString(nestedObject['code']);
  final message =
      _nonEmptyString(object['message']) ??
      _nonEmptyString(nestedObject['message']) ??
      (nested is String && nested.isNotEmpty ? nested : null);
  final hasError = nested != null || object['policy_denied'] == true;
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
    'details': object['details'] is Map
        ? Map<String, Object?>.from(object['details']! as Map)
        : const <String, Object?>{},
  };
  if (status != 'ok' && code != null) outcome['code'] = code;
  if (status != 'ok' && message != null) outcome['message'] = message;
  return outcome;
}

String? _nonEmptyString(Object? value) {
  return value is String && value.isNotEmpty ? value : null;
}

Map<String, Object?> _error(Object? id, int code, String message) {
  final response = <String, Object?>{
    'jsonrpc': '2.0',
    'error': <String, Object?>{'code': code, 'message': message},
  };
  if (id != null) response['id'] = id;
  return response;
}
