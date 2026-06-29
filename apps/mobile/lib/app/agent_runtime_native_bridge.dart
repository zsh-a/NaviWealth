/// App-level bridge for the native Rust agent-runtime contract helpers.
///
/// Generated FRB bindings expose primitive JSON string functions. This file is
/// the stable application seam: callers pass Dart maps and receive Dart maps,
/// while tests can replace the native bridge without loading the dylib.
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naviwealth/src/rust/api/agent_runtime.dart' as rust;

import '../core/ai/local/embedding/rust_gemma_embedder.dart';
import '../core/config/providers.dart';
import 'agent_runtime_catalog.dart';
import 'agent_runtime_tool_host.dart';

typedef LifeosNativeRuntimeInitializer =
    Future<void> Function({String? libraryPath});

final agentRuntimeNativeApiProvider = Provider<AgentRuntimeNativeApi>(
  (ref) => const FrbAgentRuntimeNativeApi(),
);

final agentRuntimeNativeBridgeProvider = Provider<AgentRuntimeNativeBridge>((
  ref,
) {
  final config = ref.watch(appConfigProvider);
  return FfiAgentRuntimeNativeBridge(
    api: ref.watch(agentRuntimeNativeApiProvider),
    initRuntime: initLifeosNativeRuntime,
    libraryPath: config.rustEmbedderLibraryPath.isEmpty
        ? null
        : config.rustEmbedderLibraryPath,
  );
});

final agentRuntimeNativeCatalogSummaryProvider =
    FutureProvider<Map<String, Object?>>((ref) async {
      final catalog = ref.watch(agentRuntimeCatalogProvider);
      final bridge = ref.watch(agentRuntimeNativeBridgeProvider);
      return bridge.catalogSummary(catalog.toJson());
    });

final agentRuntimeNativeStepRunnerProvider =
    Provider<AgentRuntimeNativeStepRunner>((ref) {
      return AgentRuntimeNativeStepRunner(
        bridge: ref.watch(agentRuntimeNativeBridgeProvider),
        toolHost: ref.watch(agentRuntimeToolHostProvider),
      );
    });

abstract interface class AgentRuntimeNativeApi {
  Future<String> protocolVersion();
  Future<String> catalogVersion();
  Future<String> catalogSummary({required String catalogJson});
  Future<String> validateRunRequest({required String requestJson});
  Future<String> validateTrace({required String traceJson});
  Future<String> validateToolSpec({required String toolJson});
  Future<String> startRunStep({
    required String catalogJson,
    required String requestJson,
    required String agentId,
  });
}

class FrbAgentRuntimeNativeApi implements AgentRuntimeNativeApi {
  const FrbAgentRuntimeNativeApi();

  @override
  Future<String> protocolVersion() => rust.agentRuntimeProtocolVersion();

  @override
  Future<String> catalogVersion() => rust.agentRuntimeCatalogVersion();

  @override
  Future<String> catalogSummary({required String catalogJson}) {
    return rust.agentRuntimeCatalogSummary(catalogJson: catalogJson);
  }

  @override
  Future<String> validateRunRequest({required String requestJson}) {
    return rust.agentRuntimeValidateRunRequest(requestJson: requestJson);
  }

  @override
  Future<String> validateTrace({required String traceJson}) {
    return rust.agentRuntimeValidateTrace(traceJson: traceJson);
  }

  @override
  Future<String> validateToolSpec({required String toolJson}) {
    return rust.agentRuntimeValidateToolSpec(toolJson: toolJson);
  }

  @override
  Future<String> startRunStep({
    required String catalogJson,
    required String requestJson,
    required String agentId,
  }) {
    return rust.agentRuntimeStartRunStep(
      catalogJson: catalogJson,
      requestJson: requestJson,
      agentId: agentId,
    );
  }
}

abstract interface class AgentRuntimeNativeBridge {
  Future<String> protocolVersion();
  Future<String> catalogVersion();
  Future<Map<String, Object?>> catalogSummary(Map<String, Object?> catalog);
  Future<Map<String, Object?>> validateRunRequest(Map<String, Object?> request);
  Future<Map<String, Object?>> validateTrace(Map<String, Object?> trace);
  Future<Map<String, Object?>> validateToolSpec(Map<String, Object?> tool);
  Future<Map<String, Object?>> startRunStep({
    required Map<String, Object?> catalog,
    required Map<String, Object?> request,
    required String agentId,
  });
}

class FfiAgentRuntimeNativeBridge implements AgentRuntimeNativeBridge {
  FfiAgentRuntimeNativeBridge({
    required AgentRuntimeNativeApi api,
    required LifeosNativeRuntimeInitializer initRuntime,
    String? libraryPath,
  }) : _api = api,
       _initRuntime = initRuntime,
       _libraryPath = libraryPath;

  final AgentRuntimeNativeApi _api;
  final LifeosNativeRuntimeInitializer _initRuntime;
  final String? _libraryPath;

  Future<void>? _initFuture;

  @override
  Future<String> protocolVersion() async {
    await _ensureInitialized();
    return _api.protocolVersion();
  }

  @override
  Future<String> catalogVersion() async {
    await _ensureInitialized();
    return _api.catalogVersion();
  }

  @override
  Future<Map<String, Object?>> catalogSummary(
    Map<String, Object?> catalog,
  ) async {
    await _ensureInitialized();
    final json = await _api.catalogSummary(catalogJson: jsonEncode(catalog));
    return _decodeObject(json);
  }

  @override
  Future<Map<String, Object?>> validateRunRequest(
    Map<String, Object?> request,
  ) async {
    await _ensureInitialized();
    final json = await _api.validateRunRequest(
      requestJson: jsonEncode(request),
    );
    return _decodeObject(json);
  }

  @override
  Future<Map<String, Object?>> validateTrace(Map<String, Object?> trace) async {
    await _ensureInitialized();
    final json = await _api.validateTrace(traceJson: jsonEncode(trace));
    return _decodeObject(json);
  }

  @override
  Future<Map<String, Object?>> validateToolSpec(
    Map<String, Object?> tool,
  ) async {
    await _ensureInitialized();
    final json = await _api.validateToolSpec(toolJson: jsonEncode(tool));
    return _decodeObject(json);
  }

  @override
  Future<Map<String, Object?>> startRunStep({
    required Map<String, Object?> catalog,
    required Map<String, Object?> request,
    required String agentId,
  }) async {
    await _ensureInitialized();
    final json = await _api.startRunStep(
      catalogJson: jsonEncode(catalog),
      requestJson: jsonEncode(request),
      agentId: agentId,
    );
    return _decodeObject(json);
  }

  Future<void> _ensureInitialized() {
    return _initFuture ??= _initRuntime(libraryPath: _libraryPath);
  }
}

class AgentRuntimeNativeStepRunner {
  const AgentRuntimeNativeStepRunner({
    required AgentRuntimeNativeBridge bridge,
    required AgentRuntimeToolHost toolHost,
  }) : _bridge = bridge,
       _toolHost = toolHost;

  final AgentRuntimeNativeBridge _bridge;
  final AgentRuntimeToolHost _toolHost;

  Future<Map<String, Object?>> startAndDispatchFirstToolStep({
    required Map<String, Object?> catalog,
    required Map<String, Object?> request,
    required String agentId,
  }) async {
    final step = await _bridge.startRunStep(
      catalog: catalog,
      request: request,
      agentId: agentId,
    );
    if (step['status'] != 'tool_call_requested') {
      return step;
    }

    final toolCall = _expectObject(step['tool_call'], 'tool_call');
    final name = toolCall['name'];
    if (name is! String || name.isEmpty) {
      throw const FormatException('native tool_call.name is required');
    }

    final responseLine = await _toolHost.handleLine(
      jsonEncode(<String, Object?>{
        'jsonrpc': '2.0',
        'id': _toolCallId(toolCall, step),
        'method': 'tool.call',
        'params': <String, Object?>{
          'name': name,
          'input': toolCall['input'] ?? const <String, Object?>{},
        },
      }),
    );
    final response = _decodeObject(responseLine);
    final error = response['error'];

    return <String, Object?>{
      ...step,
      'status': error == null ? 'tool_call_finished' : 'tool_call_failed',
      'tool_response': response,
      if (error == null) 'tool_result': response['result'],
      'tool_error': ?error,
    };
  }
}

Map<String, Object?> _decodeObject(String json) {
  final decoded = jsonDecode(json);
  if (decoded is! Map<String, Object?>) {
    throw const FormatException(
      'native agent-runtime response is not an object',
    );
  }
  return decoded;
}

Map<String, Object?> _expectObject(Object? value, String field) {
  if (value is Map<String, Object?>) return value;
  throw FormatException(
    'native agent-runtime response field $field is not an object',
  );
}

Object _toolCallId(Map<String, Object?> toolCall, Map<String, Object?> step) {
  final explicitId = toolCall['tool_call_id'];
  if (explicitId is String && explicitId.isNotEmpty) return explicitId;
  final runId = step['run_id'];
  if (runId is String && runId.isNotEmpty) return runId;
  return 'tool_call';
}
