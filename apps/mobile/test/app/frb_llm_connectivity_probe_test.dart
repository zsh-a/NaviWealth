import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/app/agent_runtime/frb_llm_connectivity_probe.dart';
import 'package:naviwealth/core/ai/llm_credentials/llm_connectivity.dart';
import 'package:naviwealth/core/ai/llm_credentials/llm_credentials.dart';

import 'agent_runtime_native_bridge_test_harness.dart';

void main() {
  test(
    'FrbLlmConnectivityProbe sends the editable profile through FRB',
    () async {
      final bridge = FakeAgentRuntimeNativeBridge(
        profileResponse: const <String, Object?>{
          'content': 'ok',
          'finish_reason': 'stop',
        },
      );
      final probe = FrbLlmConnectivityProbe(bridge: bridge);

      final result = await probe.probe(
        const LlmProfile(
          id: 'draft',
          name: 'Draft',
          provider: LlmProvider.openai,
          apiKey: 'sk-test',
          baseUrl: 'https://openai.test/v1',
          model: 'gpt-test',
        ),
      );

      expect(result.status, LlmProbeStatus.ok);
      expect(bridge.completeCalls, 1);
      expect(bridge.lastRequest['provider'], 'openai');
      expect(bridge.lastRequest['model'], 'gpt-test');
      expect(bridge.lastRequest['messages'], hasLength(1));
      final metadata = bridge.lastRequest['metadata']! as Map;
      expect(metadata['profile_id'], 'draft');
      expect(metadata['api_key'], 'sk-test');
      expect(metadata['base_url'], 'https://openai.test/v1');
      expect(metadata['surface'], 'settings_llm_connectivity');
    },
  );

  test('FrbLlmConnectivityProbe maps provider HTTP errors', () async {
    final probe = FrbLlmConnectivityProbe(
      bridge: FakeAgentRuntimeNativeBridge(
        profileError: StateError('provider_http_401'),
      ),
    );

    final result = await probe.probe(
      const LlmProfile(
        id: 'draft',
        name: 'Draft',
        provider: LlmProvider.anthropic,
        apiKey: 'sk-test',
      ),
    );

    expect(result.status, LlmProbeStatus.authFailed);
    expect(result.httpStatus, 401);
  });

  test('FrbLlmConnectivityProbe short-circuits keyless profiles', () async {
    final bridge = FakeAgentRuntimeNativeBridge();
    final probe = FrbLlmConnectivityProbe(bridge: bridge);

    final result = await probe.probe(
      const LlmProfile(
        id: 'draft',
        name: 'Draft',
        provider: LlmProvider.anthropic,
        apiKey: '   ',
      ),
    );

    expect(result.status, LlmProbeStatus.authFailed);
    expect(bridge.completeCalls, 0);
  });
}
