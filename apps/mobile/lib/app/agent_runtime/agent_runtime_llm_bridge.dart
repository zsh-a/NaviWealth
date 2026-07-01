/// Dart-side LLM profile adapter for the FRB agent runtime.
///
/// The user's LLM key remains device-local. This bridge only converts the
/// active [LlmProfile] into the provider-neutral `agent-llm` request shape and
/// sends it over the local FRB bridge.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ai/llm_credentials/llm_credentials.dart';
import '../../core/ai/llm_credentials/providers.dart';
import 'agent_runtime_native_bridge.dart';

final agentRuntimeLlmBridgeProvider = Provider<AgentRuntimeLlmBridge?>((ref) {
  final profile = ref.watch(llmCredentialsProvider).asData?.value?.active;
  if (profile == null || !profile.hasKey) return null;
  return AgentRuntimeLlmBridge(
    bridge: ref.watch(agentRuntimeNativeBridgeProvider),
    profile: profile,
  );
});

class AgentRuntimeLlmBridge {
  const AgentRuntimeLlmBridge({
    required AgentRuntimeNativeBridge bridge,
    required LlmProfile profile,
  }) : _bridge = bridge,
       _profile = profile;

  final AgentRuntimeNativeBridge _bridge;
  final LlmProfile _profile;

  Map<String, Object?> buildRequest({
    required List<Map<String, Object?>> messages,
    List<Map<String, Object?>> tools = const <Map<String, Object?>>[],
    double? temperature,
    int? maxOutputTokens,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    return <String, Object?>{
      'protocol_version': 'agent.v1',
      'provider': _profile.provider.wire,
      'model': _profile.model?.trim().isNotEmpty == true
          ? _profile.model!.trim()
          : _defaultModel(_profile.provider),
      'messages': messages,
      'temperature': ?temperature,
      'max_output_tokens': ?maxOutputTokens,
      'tools': tools,
      'metadata': <String, Object?>{
        ...metadata,
        'profile_id': _profile.id,
        'profile_name': _profile.displayName,
        'base_url': ?_profile.baseUrl,
        'api_key': _profile.apiKey,
      },
    };
  }

  Future<Map<String, Object?>> validateRequest({
    required List<Map<String, Object?>> messages,
    List<Map<String, Object?>> tools = const <Map<String, Object?>>[],
    double? temperature,
    int? maxOutputTokens,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    return _bridge.validateLlmRequest(
      buildRequest(
        messages: messages,
        tools: tools,
        temperature: temperature,
        maxOutputTokens: maxOutputTokens,
        metadata: metadata,
      ),
    );
  }

  Future<Map<String, Object?>> completeMock({
    required List<Map<String, Object?>> messages,
    required String responseText,
    List<Map<String, Object?>> tools = const <Map<String, Object?>>[],
    double? temperature,
    int? maxOutputTokens,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    final request = buildRequest(
      messages: messages,
      tools: tools,
      temperature: temperature,
      maxOutputTokens: maxOutputTokens,
      metadata: metadata,
    );
    return _bridge.completeMockLlm(
      request: request,
      responseText: responseText,
    );
  }

  Future<Map<String, Object?>> completeProfile({
    required List<Map<String, Object?>> messages,
    List<Map<String, Object?>> tools = const <Map<String, Object?>>[],
    double? temperature,
    int? maxOutputTokens,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    final request = buildRequest(
      messages: messages,
      tools: tools,
      temperature: temperature,
      maxOutputTokens: maxOutputTokens,
      metadata: metadata,
    );
    return _bridge.completeProfileLlm(request: request);
  }
}

String _defaultModel(LlmProvider provider) {
  return switch (provider) {
    LlmProvider.anthropic => 'claude-sonnet-4-5',
    LlmProvider.openai => 'gpt-5-mini',
  };
}
