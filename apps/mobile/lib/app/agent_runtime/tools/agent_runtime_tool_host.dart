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
      return _encode(_result(id, result));
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

Map<String, Object?> _result(Object? id, Object? result) {
  final response = <String, Object?>{'jsonrpc': '2.0', 'result': result};
  if (id != null) response['id'] = id;
  return response;
}

Map<String, Object?> _error(Object? id, int code, String message) {
  final response = <String, Object?>{
    'jsonrpc': '2.0',
    'error': <String, Object?>{'code': code, 'message': message},
  };
  if (id != null) response['id'] = id;
  return response;
}
