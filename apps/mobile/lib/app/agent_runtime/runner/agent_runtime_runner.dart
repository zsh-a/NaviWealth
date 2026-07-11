/// App-level FRB agent-runtime turn composition.
///
/// This is the Flutter composition seam for a profile-backed turn: LLM
/// completion is still delegated to the native FRB bridge, tool execution still
/// flows through the existing Dart device-tool host, and the native runtime step
/// runner remains the owner of terminal step handling.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naviwealth/app/agent_runtime/bridges/agent_runtime_llm_bridge.dart';
import 'package:naviwealth/app/agent_runtime/bridges/agent_runtime_native_bridge.dart';
import 'package:naviwealth/app/agent_runtime/catalog/agent_runtime_catalog.dart';
import 'package:naviwealth/app/agent_runtime/runner/agent_runtime_step_runner.dart';
import 'package:naviwealth/core/ai/runtime/agent_runtime/agent_runtime_profile_turn.dart'
    as core_profile_turn;

export 'package:naviwealth/core/ai/runtime/agent_runtime/agent_runtime_profile_turn.dart'
    show AgentRuntimeProfileTurnResult, agentRuntimeProfileTurnRunnerProvider;

AgentRuntimeProfileTurnRunner? buildAgentRuntimeProfileTurnRunner(Ref ref) {
  final llmBridge = ref.watch(agentRuntimeLlmBridgeProvider);
  if (llmBridge == null) return null;
  return AgentRuntimeProfileTurnRunner.lazyCatalog(
    catalogReader: () => ref.read(agentRuntimeCatalogProvider),
    llmBridge: llmBridge,
    stepRunner: ref.watch(agentRuntimeNativeStepRunnerProvider),
  );
}

class AgentRuntimeProfileTurnRunner
    implements core_profile_turn.AgentRuntimeProfileTurnRunner {
  const AgentRuntimeProfileTurnRunner({
    required AgentRuntimeCatalog catalog,
    required AgentRuntimeLlmBridge llmBridge,
    required AgentRuntimeNativeStepRunner stepRunner,
  }) : _catalog = catalog,
       _catalogReader = null,
       _llmBridge = llmBridge,
       _stepRunner = stepRunner;

  const AgentRuntimeProfileTurnRunner.lazyCatalog({
    required AgentRuntimeCatalog Function() catalogReader,
    required AgentRuntimeLlmBridge llmBridge,
    required AgentRuntimeNativeStepRunner stepRunner,
  }) : _catalog = null,
       _catalogReader = catalogReader,
       _llmBridge = llmBridge,
       _stepRunner = stepRunner;

  final AgentRuntimeCatalog? _catalog;
  final AgentRuntimeCatalog Function()? _catalogReader;
  final AgentRuntimeLlmBridge _llmBridge;
  final AgentRuntimeNativeStepRunner _stepRunner;

  @override
  Future<core_profile_turn.AgentRuntimeProfileTurnResult> run({
    required String agentId,
    required List<Map<String, Object?>> messages,
    List<Map<String, Object?>> tools = const <Map<String, Object?>>[],
    double? temperature,
    int? maxOutputTokens,
    Map<String, Object?> metadata = const <String, Object?>{},
    int? maxEffectSteps,
  }) async {
    final catalog = _catalogReader?.call() ?? _catalog!;
    final catalogJson = catalog.toJson();
    final llmRequest = _llmBridge.buildRequest(
      messages: messages,
      tools: tools,
      temperature: temperature,
      maxOutputTokens: maxOutputTokens,
      metadata: metadata,
    );
    final bridge = _stepRunner.bridge;
    if (bridge is AgentRuntimeSnapshotBridge) {
      final snapshotBridge = bridge as AgentRuntimeSnapshotBridge;
      final limit = maxEffectSteps ?? _stepRunner.defaultMaxEffectSteps;
      if (limit < 0) {
        throw RangeError.value(limit, 'maxEffectSteps', 'must be non-negative');
      }
      final nativeTurn = await snapshotBridge.startProfileTurnSnapshot(
        catalog: catalogJson,
        llmRequest: llmRequest,
        agentId: agentId,
        runMetadata: metadata,
        maxEffectSteps: limit,
        maxSubagentDepth: _stepRunner.defaultMaxSubagentDepth,
      );
      _expectProtocolVersion(nativeTurn);
      final llmResponse = _expectObject(
        nativeTurn['llm_response'],
        'llm_response',
      );
      final initialSnapshot = _expectObject(nativeTurn['snapshot'], 'snapshot');
      final stepRun = await _stepRunner.continueSnapshotUntilTerminalWithTrace(
        catalog: catalogJson,
        initialSnapshot: initialSnapshot,
        agentId: agentId,
      );
      return core_profile_turn.AgentRuntimeProfileTurnResult(
        llmResponse: llmResponse,
        step: stepRun.terminalStep,
        stepRun: stepRun,
      );
    }
    final nativeTurn = await bridge.startProfileTurnStep(
      catalog: catalogJson,
      llmRequest: llmRequest,
      agentId: agentId,
      runMetadata: metadata,
    );
    _expectProtocolVersion(nativeTurn);
    final llmResponse = _expectObject(
      nativeTurn['llm_response'],
      'llm_response',
    );
    final initialStep = _expectObject(nativeTurn['step'], 'step');
    final stepRun = await _stepRunner.continueUntilTerminalWithTrace(
      catalog: catalogJson,
      initialStep: initialStep,
      agentId: agentId,
      maxEffectSteps: maxEffectSteps,
    );
    return core_profile_turn.AgentRuntimeProfileTurnResult(
      llmResponse: llmResponse,
      step: stepRun.terminalStep,
      stepRun: stepRun,
    );
  }
}

void _expectProtocolVersion(Map<String, Object?> nativeTurn) {
  final version = nativeTurn['protocol_version'];
  if (version != kAgentRuntimeProtocolVersion) {
    throw FormatException(
      'agent runtime native turn protocol_version must be $kAgentRuntimeProtocolVersion',
      version,
    );
  }
}

Map<String, Object?> _expectObject(Object? value, String field) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  throw FormatException('agent runtime native turn field $field is not object');
}
