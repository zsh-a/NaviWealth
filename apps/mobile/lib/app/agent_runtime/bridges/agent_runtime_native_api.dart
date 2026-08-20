/// Raw flutter_rust_bridge adapter for the embedded agent runtime.
library;

import 'package:naviwealth/src/rust/api/agent_runtime.dart' as rust;

export 'package:naviwealth/core/native/lifeos_native_runtime.dart'
    show LifeosNativeRuntimeInitializer;

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
}

abstract interface class AgentRuntimeSnapshotNativeApi {
  Future<String> startProfileTurnSnapshot({
    required String catalogJson,
    required String llmRequestJson,
    required String agentId,
    required String runMetadataJson,
    required int maxEffectSteps,
    required int maxSubagentDepth,
  });
  Future<String> startRunSnapshot({
    required String catalogJson,
    required String requestJson,
    required String agentId,
    required int maxEffectSteps,
    required int maxSubagentDepth,
  });
  Future<String> continueRunSnapshot({
    required String catalogJson,
    required String snapshotJson,
    required String effectResponseJson,
    required String agentId,
  });
  Future<String> startRequestedSubagentSnapshot({
    required String catalogJson,
    required String parentSnapshotJson,
  });
  Future<String> resumeParentFromSubagentSnapshot({
    required String catalogJson,
    required String parentSnapshotJson,
    required String childSnapshotJson,
  });
}

abstract interface class AgentRuntimeSnapshotControlNativeApi {
  Future<String> cancelRunSnapshot({
    required String catalogJson,
    required String snapshotJson,
    required String agentId,
    required String reason,
  });
}

abstract interface class AgentRuntimeHostNativeApi
    implements
        AgentRuntimeNativeApi,
        AgentRuntimeSnapshotNativeApi,
        AgentRuntimeSnapshotControlNativeApi {}

class FrbAgentRuntimeNativeApi implements AgentRuntimeHostNativeApi {
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
  Future<String> startRunSnapshot({
    required String catalogJson,
    required String requestJson,
    required String agentId,
    required int maxEffectSteps,
    required int maxSubagentDepth,
  }) {
    return rust.agentRuntimeStartRunSnapshot(
      catalogJson: catalogJson,
      requestJson: requestJson,
      agentId: agentId,
      maxEffectSteps: maxEffectSteps,
      maxSubagentDepth: maxSubagentDepth,
    );
  }

  @override
  Future<String> startProfileTurnSnapshot({
    required String catalogJson,
    required String llmRequestJson,
    required String agentId,
    required String runMetadataJson,
    required int maxEffectSteps,
    required int maxSubagentDepth,
  }) {
    return rust.agentRuntimeStartProfileTurnSnapshot(
      catalogJson: catalogJson,
      llmRequestJson: llmRequestJson,
      agentId: agentId,
      runMetadataJson: runMetadataJson,
      maxEffectSteps: maxEffectSteps,
      maxSubagentDepth: maxSubagentDepth,
    );
  }

  @override
  Future<String> continueRunSnapshot({
    required String catalogJson,
    required String snapshotJson,
    required String effectResponseJson,
    required String agentId,
  }) {
    return rust.agentRuntimeContinueRunSnapshot(
      catalogJson: catalogJson,
      snapshotJson: snapshotJson,
      effectResponseJson: effectResponseJson,
      agentId: agentId,
    );
  }

  @override
  Future<String> cancelRunSnapshot({
    required String catalogJson,
    required String snapshotJson,
    required String agentId,
    required String reason,
  }) {
    return rust.agentRuntimeCancelRunSnapshot(
      catalogJson: catalogJson,
      snapshotJson: snapshotJson,
      agentId: agentId,
      reason: reason,
    );
  }

  @override
  Future<String> startRequestedSubagentSnapshot({
    required String catalogJson,
    required String parentSnapshotJson,
  }) {
    return rust.agentRuntimeStartRequestedSubagentSnapshot(
      catalogJson: catalogJson,
      parentSnapshotJson: parentSnapshotJson,
    );
  }

  @override
  Future<String> resumeParentFromSubagentSnapshot({
    required String catalogJson,
    required String parentSnapshotJson,
    required String childSnapshotJson,
  }) {
    return rust.agentRuntimeResumeParentFromSubagentSnapshot(
      catalogJson: catalogJson,
      parentSnapshotJson: parentSnapshotJson,
      childSnapshotJson: childSnapshotJson,
    );
  }
}
