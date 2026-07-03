/// App-level bridge for the native Rust agent-runtime contract helpers.
///
/// Generated FRB bindings expose primitive JSON string functions. This file is
/// the stable application seam: callers pass Dart maps and receive Dart maps,
/// while tests can replace the native bridge without loading the dylib.
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naviwealth/app/agent_runtime/catalog/agent_runtime_catalog.dart';
import 'package:naviwealth/core/ai/local/embedding/rust_gemma_embedder.dart';
import 'package:naviwealth/core/ai/runtime/agent_runtime/agent_runtime_json.dart';
import 'package:naviwealth/core/config/providers.dart';
import 'package:naviwealth/src/rust/api/agent_runtime.dart' as rust;

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
  Future<String> validateLlmRequest({required String requestJson});
  Future<String> validateLlmResponse({required String responseJson});
  Future<String> completeMockLlm({
    required String requestJson,
    required String responseText,
  });
  Future<String> completeProfileLlm({required String requestJson});
  Future<String> startProfileTurnStep({
    required String catalogJson,
    required String llmRequestJson,
    required String agentId,
    required String runMetadataJson,
  });
  Future<String> startRunStep({
    required String catalogJson,
    required String requestJson,
    required String agentId,
  });
  Future<String> continueRunStep({
    required String catalogJson,
    required String previousStepJson,
    required String toolResponseJson,
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
  Future<String> validateLlmRequest({required String requestJson}) {
    return rust.agentRuntimeValidateLlmRequest(requestJson: requestJson);
  }

  @override
  Future<String> validateLlmResponse({required String responseJson}) {
    return rust.agentRuntimeValidateLlmResponse(responseJson: responseJson);
  }

  @override
  Future<String> completeMockLlm({
    required String requestJson,
    required String responseText,
  }) {
    return rust.agentRuntimeCompleteMockLlm(
      requestJson: requestJson,
      responseText: responseText,
    );
  }

  @override
  Future<String> completeProfileLlm({required String requestJson}) {
    return rust.agentRuntimeCompleteProfileLlm(requestJson: requestJson);
  }

  @override
  Future<String> startProfileTurnStep({
    required String catalogJson,
    required String llmRequestJson,
    required String agentId,
    required String runMetadataJson,
  }) {
    return rust.agentRuntimeStartProfileTurnStep(
      catalogJson: catalogJson,
      llmRequestJson: llmRequestJson,
      agentId: agentId,
      runMetadataJson: runMetadataJson,
    );
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

  @override
  Future<String> continueRunStep({
    required String catalogJson,
    required String previousStepJson,
    required String toolResponseJson,
    required String agentId,
  }) {
    return rust.agentRuntimeContinueRunStep(
      catalogJson: catalogJson,
      previousStepJson: previousStepJson,
      toolResponseJson: toolResponseJson,
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
  Future<Map<String, Object?>> validateLlmRequest(Map<String, Object?> request);
  Future<Map<String, Object?>> validateLlmResponse(
    Map<String, Object?> response,
  );
  Future<Map<String, Object?>> completeMockLlm({
    required Map<String, Object?> request,
    required String responseText,
  });
  Future<Map<String, Object?>> completeProfileLlm({
    required Map<String, Object?> request,
  });
  Future<Map<String, Object?>> startProfileTurnStep({
    required Map<String, Object?> catalog,
    required Map<String, Object?> llmRequest,
    required String agentId,
    required Map<String, Object?> runMetadata,
  });
  Future<Map<String, Object?>> startRunStep({
    required Map<String, Object?> catalog,
    required Map<String, Object?> request,
    required String agentId,
  });
  Future<Map<String, Object?>> continueRunStep({
    required Map<String, Object?> catalog,
    required Map<String, Object?> previousStep,
    required Map<String, Object?> toolResponse,
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
  Future<Map<String, Object?>> validateLlmRequest(
    Map<String, Object?> request,
  ) async {
    await _ensureInitialized();
    final json = await _api.validateLlmRequest(
      requestJson: jsonEncode(request),
    );
    return _decodeObject(json);
  }

  @override
  Future<Map<String, Object?>> validateLlmResponse(
    Map<String, Object?> response,
  ) async {
    await _ensureInitialized();
    final json = await _api.validateLlmResponse(
      responseJson: jsonEncode(response),
    );
    return _decodeObject(json);
  }

  @override
  Future<Map<String, Object?>> completeMockLlm({
    required Map<String, Object?> request,
    required String responseText,
  }) async {
    await _ensureInitialized();
    final json = await _api.completeMockLlm(
      requestJson: jsonEncode(request),
      responseText: responseText,
    );
    return _decodeObject(json);
  }

  @override
  Future<Map<String, Object?>> completeProfileLlm({
    required Map<String, Object?> request,
  }) async {
    await _ensureInitialized();
    final json = await _api.completeProfileLlm(
      requestJson: jsonEncode(request),
    );
    return _decodeObject(json);
  }

  @override
  Future<Map<String, Object?>> startProfileTurnStep({
    required Map<String, Object?> catalog,
    required Map<String, Object?> llmRequest,
    required String agentId,
    required Map<String, Object?> runMetadata,
  }) async {
    await _ensureInitialized();
    final json = await _api.startProfileTurnStep(
      catalogJson: jsonEncode(catalog),
      llmRequestJson: jsonEncode(llmRequest),
      agentId: agentId,
      runMetadataJson: jsonEncode(runMetadata),
    );
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

  @override
  Future<Map<String, Object?>> continueRunStep({
    required Map<String, Object?> catalog,
    required Map<String, Object?> previousStep,
    required Map<String, Object?> toolResponse,
    required String agentId,
  }) async {
    await _ensureInitialized();
    final json = await _api.continueRunStep(
      catalogJson: jsonEncode(catalog),
      previousStepJson: jsonEncode(previousStep),
      toolResponseJson: jsonEncode(toolResponse),
      agentId: agentId,
    );
    return _decodeObject(json);
  }

  Future<void> _ensureInitialized() {
    return _initFuture ??= _initRuntime(libraryPath: _libraryPath);
  }
}

Map<String, Object?> _decodeObject(String json) {
  return agentRuntimeDecodeObject(json, label: 'native agent-runtime response');
}
