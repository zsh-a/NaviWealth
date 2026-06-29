import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/app/agent_runtime_native_bridge.dart';
import 'package:naviwealth/app/frb_llm_connectivity_probe.dart';
import 'package:naviwealth/core/ai/llm_credentials/llm_connectivity.dart';
import 'package:naviwealth/core/ai/llm_credentials/llm_credentials.dart';

void main() {
  test(
    'FrbLlmConnectivityProbe sends the editable profile through FRB',
    () async {
      final bridge = _FakeNativeBridge();
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
      bridge: _FakeNativeBridge(error: StateError('provider_http_401')),
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
    final bridge = _FakeNativeBridge();
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

class _FakeNativeBridge implements AgentRuntimeNativeBridge {
  _FakeNativeBridge({this.error});

  final Object? error;
  var completeCalls = 0;
  Map<String, Object?> lastRequest = const <String, Object?>{};

  @override
  Future<Map<String, Object?>> completeProfileLlm({
    required Map<String, Object?> request,
  }) async {
    completeCalls += 1;
    lastRequest = request;
    final e = error;
    if (e != null) throw e;
    return <String, Object?>{
      'provider': request['provider'],
      'model': request['model'],
      'content': 'ok',
      'finish_reason': 'stop',
    };
  }

  @override
  Future<Map<String, Object?>> catalogSummary(Map<String, Object?> catalog) {
    throw UnimplementedError();
  }

  @override
  Future<String> catalogVersion() {
    throw UnimplementedError();
  }

  @override
  Future<Map<String, Object?>> completeMockLlm({
    required Map<String, Object?> request,
    required String responseText,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Map<String, Object?>> continueRunStep({
    required Map<String, Object?> catalog,
    required Map<String, Object?> previousStep,
    required Map<String, Object?> toolResponse,
    required String agentId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<String> protocolVersion() {
    throw UnimplementedError();
  }

  @override
  Future<Map<String, Object?>> startProfileTurnStep({
    required Map<String, Object?> catalog,
    required Map<String, Object?> llmRequest,
    required String agentId,
    required Map<String, Object?> runMetadata,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Map<String, Object?>> startRunStep({
    required Map<String, Object?> catalog,
    required Map<String, Object?> request,
    required String agentId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Map<String, Object?>> validateLlmRequest(
    Map<String, Object?> request,
  ) {
    throw UnimplementedError();
  }

  @override
  Future<Map<String, Object?>> validateLlmResponse(
    Map<String, Object?> response,
  ) {
    throw UnimplementedError();
  }

  @override
  Future<Map<String, Object?>> validateRunRequest(
    Map<String, Object?> request,
  ) {
    throw UnimplementedError();
  }

  @override
  Future<Map<String, Object?>> validateToolSpec(Map<String, Object?> tool) {
    throw UnimplementedError();
  }

  @override
  Future<Map<String, Object?>> validateTrace(Map<String, Object?> trace) {
    throw UnimplementedError();
  }
}
