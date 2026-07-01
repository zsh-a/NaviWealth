/// App-level FRB agent-runtime turn composition.
///
/// This is the Flutter composition seam for a profile-backed turn: LLM
/// completion is still delegated to the native FRB bridge, tool execution still
/// flows through the existing Dart device-tool host, and the native runtime step
/// runner remains the owner of terminal step handling.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'agent_runtime_catalog.dart';
import 'agent_runtime_llm_bridge.dart';
import 'agent_runtime_step_runner.dart';

final agentRuntimeProfileTurnRunnerProvider =
    Provider<AgentRuntimeProfileTurnRunner?>((ref) {
      final llmBridge = ref.watch(agentRuntimeLlmBridgeProvider);
      if (llmBridge == null) return null;
      return AgentRuntimeProfileTurnRunner.lazyCatalog(
        catalogReader: () => ref.read(agentRuntimeCatalogProvider),
        llmBridge: llmBridge,
        stepRunner: ref.watch(agentRuntimeNativeStepRunnerProvider),
      );
    });

class AgentRuntimeProfileTurnRunner {
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

  Future<AgentRuntimeProfileTurnResult> run({
    required String agentId,
    required List<Map<String, Object?>> messages,
    List<Map<String, Object?>> tools = const <Map<String, Object?>>[],
    double? temperature,
    int? maxOutputTokens,
    Map<String, Object?> metadata = const <String, Object?>{},
    int? maxToolSteps,
  }) async {
    final catalog = _catalogReader?.call() ?? _catalog!;
    final nativeTurn = await _stepRunner.bridge.startProfileTurnStep(
      catalog: catalog.toJson(),
      llmRequest: _llmBridge.buildRequest(
        messages: messages,
        tools: tools,
        temperature: temperature,
        maxOutputTokens: maxOutputTokens,
        metadata: metadata,
      ),
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
      catalog: catalog.toJson(),
      initialStep: initialStep,
      agentId: agentId,
      maxToolSteps: maxToolSteps,
    );
    return AgentRuntimeProfileTurnResult(
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

class AgentRuntimeProfileTurnResult {
  const AgentRuntimeProfileTurnResult({
    required this.llmResponse,
    required this.step,
    this.stepRun = const AgentRuntimeNativeStepRunResult(
      terminalStep: <String, Object?>{},
    ),
  });

  final Map<String, Object?> llmResponse;
  final Map<String, Object?> step;
  final AgentRuntimeNativeStepRunResult stepRun;

  Map<String, Object?> toJson() => <String, Object?>{
    'llm_response': llmResponse,
    'step': step,
    'step_run': stepRun.toJson(),
  };
}
