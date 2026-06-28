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

abstract interface class AgentRuntimeNativeApi {
  Future<String> protocolVersion();
  Future<String> catalogVersion();
  Future<String> catalogSummary({required String catalogJson});
  Future<String> validateRunRequest({required String requestJson});
  Future<String> validateTrace({required String traceJson});
  Future<String> validateToolSpec({required String toolJson});
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
}

abstract interface class AgentRuntimeNativeBridge {
  Future<String> protocolVersion();
  Future<String> catalogVersion();
  Future<Map<String, Object?>> catalogSummary(Map<String, Object?> catalog);
  Future<Map<String, Object?>> validateRunRequest(Map<String, Object?> request);
  Future<Map<String, Object?>> validateTrace(Map<String, Object?> trace);
  Future<Map<String, Object?>> validateToolSpec(Map<String, Object?> tool);
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

  Future<void> _ensureInitialized() {
    return _initFuture ??= _initRuntime(libraryPath: _libraryPath);
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
