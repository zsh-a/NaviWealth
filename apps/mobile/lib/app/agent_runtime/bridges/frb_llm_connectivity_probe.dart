/// FRB-backed one-tap connectivity probe for editable LLM profiles.
library;

import 'dart:async';

import 'package:naviwealth/app/agent_runtime/bridges/agent_runtime_llm_bridge.dart';
import 'package:naviwealth/app/agent_runtime/bridges/agent_runtime_native_bridge.dart';
import 'package:naviwealth/core/ai/llm_credentials/llm_connectivity.dart';
import 'package:naviwealth/core/ai/llm_credentials/llm_credentials.dart';

class FrbLlmConnectivityProbe implements LlmConnectivityProbe {
  const FrbLlmConnectivityProbe({required AgentRuntimeNativeBridge bridge})
    : _bridge = bridge;

  final AgentRuntimeNativeBridge _bridge;

  @override
  Future<LlmProbeResult> probe(
    LlmProfile profile, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    if (!profile.hasKey) {
      return const LlmProbeResult(LlmProbeStatus.authFailed, '请先填入 API Key');
    }
    final llmBridge = AgentRuntimeLlmBridge(bridge: _bridge, profile: profile);
    try {
      await llmBridge
          .completeProfile(
            messages: const <Map<String, Object?>>[
              <String, Object?>{'role': 'user', 'content': 'ping'},
            ],
            maxOutputTokens: 1,
            metadata: const <String, Object?>{
              'surface': 'settings_llm_connectivity',
              'agent_id': 'settings_llm_connectivity',
            },
          )
          .timeout(timeout);
      return const LlmProbeResult(LlmProbeStatus.ok, '连通正常 · 配置可用');
    } on TimeoutException {
      return const LlmProbeResult(
        LlmProbeStatus.network,
        '请求超时 · 检查网络或 Base URL',
      );
    } on Object catch (e) {
      return _classifyFrbProbeError(e);
    }
  }
}

LlmProbeResult _classifyFrbProbeError(Object error) {
  final message = error.toString();
  final status = _extractHttpStatus(message);
  if (status != null) {
    return classifyLlmProbeFailure(statusCode: status, message: message);
  }
  if (message.contains('metadata.api_key')) {
    return const LlmProbeResult(LlmProbeStatus.authFailed, '请先填入 API Key');
  }
  return LlmProbeResult(LlmProbeStatus.unknown, '测试失败：$message');
}

int? _extractHttpStatus(String message) {
  final match = RegExp(r'provider_http_(\d{3})').firstMatch(message);
  if (match != null) return int.tryParse(match.group(1)!);
  final httpMatch = RegExp(r'HTTP\s+(\d{3})').firstMatch(message);
  if (httpMatch != null) return int.tryParse(httpMatch.group(1)!);
  return null;
}
