/// App-level bridge for the native Rust agent-runtime contract helpers.
///
/// Generated FRB bindings expose primitive JSON string functions. This file is
/// the stable application seam: callers pass Dart maps and receive Dart maps,
/// while tests can replace the native bridge without loading the dylib.
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naviwealth/app/agent_runtime/agent_runtime_storage_policy.dart';
import 'package:naviwealth/app/agent_runtime/bridges/agent_runtime_native_api.dart';
import 'package:naviwealth/app/agent_runtime/catalog/agent_runtime_catalog.dart';
import 'package:naviwealth/core/ai/runtime/agent_runtime/agent_runtime_json.dart';
import 'package:naviwealth/core/config/providers.dart';
import 'package:naviwealth/core/native/lifeos_native_runtime.dart';

export 'package:naviwealth/app/agent_runtime/bridges/agent_runtime_native_api.dart';

final agentRuntimeNativeApiProvider = Provider<AgentRuntimeHostNativeApi>(
  (ref) => const FrbAgentRuntimeNativeApi(),
);

final agentRuntimeNativeBridgeProvider = Provider<AgentRuntimeHostBridge>((
  ref,
) {
  final config = ref.watch(appConfigProvider);
  return FfiAgentRuntimeNativeBridge(
    api: ref.watch(agentRuntimeNativeApiProvider),
    initRuntime: initLifeosNativeRuntime,
    libraryPath: config.rustEmbedderLibraryPath.isEmpty
        ? null
        : config.rustEmbedderLibraryPath,
    storagePolicy: ref.watch(agentRuntimeStoragePolicyProvider),
  );
});

final agentRuntimeNativeCatalogSummaryProvider =
    FutureProvider<Map<String, Object?>>((ref) async {
      final catalog = ref.watch(agentRuntimeCatalogProvider);
      final bridge = ref.watch(agentRuntimeNativeBridgeProvider);
      return bridge.catalogSummary(catalog.toJson());
    });

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
}

abstract interface class AgentRuntimeSnapshotBridge {
  Future<Map<String, Object?>> startProfileTurnSnapshot({
    required Map<String, Object?> catalog,
    required Map<String, Object?> llmRequest,
    required String agentId,
    required Map<String, Object?> runMetadata,
    required int maxEffectSteps,
    required int maxSubagentDepth,
  });
  Future<Map<String, Object?>> startRunSnapshot({
    required Map<String, Object?> catalog,
    required Map<String, Object?> request,
    required String agentId,
    required int maxEffectSteps,
    required int maxSubagentDepth,
  });
  Future<Map<String, Object?>> continueRunSnapshot({
    required Map<String, Object?> catalog,
    required Map<String, Object?> snapshot,
    required Map<String, Object?> effectResponse,
    required String agentId,
  });
  Future<Map<String, Object?>> startRequestedSubagentSnapshot({
    required Map<String, Object?> catalog,
    required Map<String, Object?> parentSnapshot,
  });
  Future<Map<String, Object?>> resumeParentFromSubagentSnapshot({
    required Map<String, Object?> catalog,
    required Map<String, Object?> parentSnapshot,
    required Map<String, Object?> childSnapshot,
  });
}

abstract interface class AgentRuntimeSnapshotControlBridge {
  Future<Map<String, Object?>> cancelRunSnapshot({
    required Map<String, Object?> catalog,
    required Map<String, Object?> snapshot,
    required String agentId,
    required String reason,
  });
}

abstract interface class AgentRuntimeExecutionBridge
    implements AgentRuntimeSnapshotBridge, AgentRuntimeSnapshotControlBridge {}

abstract interface class AgentRuntimeHostBridge
    implements AgentRuntimeNativeBridge, AgentRuntimeExecutionBridge {}

class FfiAgentRuntimeNativeBridge implements AgentRuntimeHostBridge {
  FfiAgentRuntimeNativeBridge({
    required AgentRuntimeHostNativeApi api,
    required LifeosNativeRuntimeInitializer initRuntime,
    String? libraryPath,
    AgentRuntimeStoragePolicy storagePolicy =
        const AgentRuntimeStoragePolicy.appOwned(),
  }) : _api = api,
       _initRuntime = initRuntime,
       _libraryPath = libraryPath,
       _storagePolicy = storagePolicy;

  final AgentRuntimeHostNativeApi _api;
  final LifeosNativeRuntimeInitializer _initRuntime;
  final String? _libraryPath;
  final AgentRuntimeStoragePolicy _storagePolicy;

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
  Future<Map<String, Object?>> startProfileTurnSnapshot({
    required Map<String, Object?> catalog,
    required Map<String, Object?> llmRequest,
    required String agentId,
    required Map<String, Object?> runMetadata,
    required int maxEffectSteps,
    required int maxSubagentDepth,
  }) async {
    await _ensureInitialized();
    final json = await _api.startProfileTurnSnapshot(
      catalogJson: jsonEncode(catalog),
      llmRequestJson: jsonEncode(llmRequest),
      agentId: agentId,
      runMetadataJson: jsonEncode(runMetadata),
      maxEffectSteps: maxEffectSteps,
      maxSubagentDepth: maxSubagentDepth,
    );
    return _decodeObject(json);
  }

  @override
  Future<Map<String, Object?>> startRunSnapshot({
    required Map<String, Object?> catalog,
    required Map<String, Object?> request,
    required String agentId,
    required int maxEffectSteps,
    required int maxSubagentDepth,
  }) async {
    await _ensureInitialized();
    final json = await _api.startRunSnapshot(
      catalogJson: jsonEncode(catalog),
      requestJson: jsonEncode(request),
      agentId: agentId,
      maxEffectSteps: maxEffectSteps,
      maxSubagentDepth: maxSubagentDepth,
    );
    return _decodeObject(json);
  }

  @override
  Future<Map<String, Object?>> continueRunSnapshot({
    required Map<String, Object?> catalog,
    required Map<String, Object?> snapshot,
    required Map<String, Object?> effectResponse,
    required String agentId,
  }) async {
    await _ensureInitialized();
    final json = await _api.continueRunSnapshot(
      catalogJson: jsonEncode(catalog),
      snapshotJson: jsonEncode(snapshot),
      effectResponseJson: jsonEncode(effectResponse),
      agentId: agentId,
    );
    return _decodeObject(json);
  }

  @override
  Future<Map<String, Object?>> cancelRunSnapshot({
    required Map<String, Object?> catalog,
    required Map<String, Object?> snapshot,
    required String agentId,
    required String reason,
  }) async {
    await _ensureInitialized();
    final json = await _api.cancelRunSnapshot(
      catalogJson: jsonEncode(catalog),
      snapshotJson: jsonEncode(snapshot),
      agentId: agentId,
      reason: reason,
    );
    return _decodeObject(json);
  }

  @override
  Future<Map<String, Object?>> startRequestedSubagentSnapshot({
    required Map<String, Object?> catalog,
    required Map<String, Object?> parentSnapshot,
  }) async {
    await _ensureInitialized();
    final json = await _api.startRequestedSubagentSnapshot(
      catalogJson: jsonEncode(catalog),
      parentSnapshotJson: jsonEncode(parentSnapshot),
    );
    return _decodeObject(json);
  }

  @override
  Future<Map<String, Object?>> resumeParentFromSubagentSnapshot({
    required Map<String, Object?> catalog,
    required Map<String, Object?> parentSnapshot,
    required Map<String, Object?> childSnapshot,
  }) async {
    await _ensureInitialized();
    final json = await _api.resumeParentFromSubagentSnapshot(
      catalogJson: jsonEncode(catalog),
      parentSnapshotJson: jsonEncode(parentSnapshot),
      childSnapshotJson: jsonEncode(childSnapshot),
    );
    return _decodeObject(json);
  }

  Future<void> _ensureInitialized() {
    _storagePolicy.requireAppOwned(surface: 'agent-runtime native bridge');
    return _initFuture ??= _initRuntime(libraryPath: _libraryPath);
  }
}

Map<String, Object?> _decodeObject(String json) {
  return agentRuntimeDecodeObject(json, label: 'native agent-runtime response');
}
