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
import 'agent_runtime_native_bridge.dart';

final agentRuntimeProfileTurnRunnerProvider =
    Provider<AgentRuntimeProfileTurnRunner?>((ref) {
      final llmBridge = ref.watch(agentRuntimeLlmBridgeProvider);
      if (llmBridge == null) return null;
      return AgentRuntimeProfileTurnRunner(
        catalog: ref.watch(agentRuntimeCatalogProvider),
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
       _llmBridge = llmBridge,
       _stepRunner = stepRunner;

  final AgentRuntimeCatalog _catalog;
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
    final llmResponse = await _llmBridge.completeProfile(
      messages: messages,
      tools: tools,
      temperature: temperature,
      maxOutputTokens: maxOutputTokens,
      metadata: metadata,
    );
    final step = await _stepRunner.runUntilTerminal(
      catalog: _catalog.toJson(),
      request: <String, Object?>{
        'protocol_version': kAgentRuntimeProtocolVersion,
        'input': _runtimeInputFromLlmResponse(llmResponse),
        'metadata': <String, Object?>{...metadata, 'llm_response': llmResponse},
      },
      agentId: agentId,
      maxToolSteps: maxToolSteps,
    );
    return AgentRuntimeProfileTurnResult(llmResponse: llmResponse, step: step);
  }
}

class AgentRuntimeProfileTurnResult {
  const AgentRuntimeProfileTurnResult({
    required this.llmResponse,
    required this.step,
  });

  final Map<String, Object?> llmResponse;
  final Map<String, Object?> step;

  Map<String, Object?> toJson() => <String, Object?>{
    'llm_response': llmResponse,
    'step': step,
  };
}

Map<String, Object?> _runtimeInputFromLlmResponse(
  Map<String, Object?> llmResponse,
) {
  final metadata = llmResponse['metadata'];
  if (metadata is Map<String, Object?>) {
    final toolCall = metadata['tool_call'];
    if (toolCall is Map<String, Object?>) {
      return <String, Object?>{
        'tool_call': toolCall,
        'llm_response': llmResponse,
      };
    }
  }
  return <String, Object?>{
    'content': llmResponse['content'],
    'llm_response': llmResponse,
  };
}
