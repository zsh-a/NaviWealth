import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/app/agent_runtime/bridges/agent_runtime_llm_bridge.dart';
import 'package:naviwealth/app/agent_runtime/bridges/agent_runtime_profile_completion_clients.dart';
import 'package:naviwealth/core/ai/contracts/contracts.dart';

void main() {
  test('Ingest FRB completion trace keeps vision routing reason', () async {
    final records = <Map<String, Object?>>[];
    final client = FrbIngestLlmProfileClient(
      llmBridge: _FakeLlmBridge(
        response: const <String, Object?>{'content': 'parsed'},
      ),
      recordTrace:
          ({
            required String agentId,
            required Map<String, Object?>? llmResponse,
            DateTime? startedAt,
            DateTime? finishedAt,
            String? requestId,
            String domain = '',
            String surface = '',
            String routingReason = '',
            Object? error,
          }) async {
            records.add(<String, Object?>{
              'agent_id': agentId,
              'domain': domain,
              'surface': surface,
              'routing_reason': routingReason,
              'error': error,
            });
            return null;
          },
    );

    await client.completeProfile(
      messages: const <Map<String, Object?>>[
        <String, Object?>{'role': 'user', 'content': 'parse image'},
      ],
      metadata: const <String, Object?>{
        'agent_id': 'finance_vision_ingest',
        'surface': 'finance_vision_ingest',
      },
    );

    expect(records.single['agent_id'], 'finance_vision_ingest');
    expect(records.single['domain'], 'finance');
    expect(records.single['surface'], 'finance_vision_ingest');
    expect(records.single['routing_reason'], kFrbVisionIngestRoutingReason);
    expect(records.single['error'], isNull);
  });
}

class _FakeLlmBridge implements AgentRuntimeLlmBridge {
  _FakeLlmBridge({this.response = const <String, Object?>{}});

  final Map<String, Object?> response;

  @override
  Map<String, Object?> buildRequest({
    required List<Map<String, Object?>> messages,
    List<Map<String, Object?>> tools = const <Map<String, Object?>>[],
    double? temperature,
    int? maxOutputTokens,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    return <String, Object?>{
      'messages': messages,
      'tools': tools,
      'metadata': metadata,
    };
  }

  @override
  Future<Map<String, Object?>> completeMock({
    required List<Map<String, Object?>> messages,
    required String responseText,
    List<Map<String, Object?>> tools = const <Map<String, Object?>>[],
    double? temperature,
    int? maxOutputTokens,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Map<String, Object?>> completeProfile({
    required List<Map<String, Object?>> messages,
    List<Map<String, Object?>> tools = const <Map<String, Object?>>[],
    double? temperature,
    int? maxOutputTokens,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) async {
    return response;
  }

  @override
  Future<Map<String, Object?>> validateRequest({
    required List<Map<String, Object?>> messages,
    List<Map<String, Object?>> tools = const <Map<String, Object?>>[],
    double? temperature,
    int? maxOutputTokens,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    throw UnimplementedError();
  }
}
