import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/app/agent_runtime/agent_runtime_llm_bridge.dart';
import 'package:naviwealth/app/agent_runtime/agent_runtime_profile_completion_clients.dart';
import 'package:naviwealth/core/ai/contracts/contracts.dart';

void main() {
  test('Knowledge FRB trace write failure does not mask success', () async {
    final client = FrbKnowledgeLlmProfileClient(
      llmBridge: _FakeLlmBridge(
        response: const <String, Object?>{'content': 'ok'},
      ),
      recordTrace: _throwingTrace,
    );

    final response = await client.completeProfile(
      messages: const <Map<String, Object?>>[
        <String, Object?>{'role': 'user', 'content': 'classify'},
      ],
      metadata: const <String, Object?>{
        'agent_id': 'knowledge_inbox_triage',
        'surface': 'knowledge_inbox_triage',
      },
    );

    expect(response['content'], 'ok');
  });

  test('Knowledge FRB trace write failure preserves provider error', () async {
    final providerError = StateError('provider failed');
    final client = FrbKnowledgeLlmProfileClient(
      llmBridge: _FakeLlmBridge(error: providerError),
      recordTrace: _throwingTrace,
    );

    await expectLater(
      client.completeProfile(
        messages: const <Map<String, Object?>>[
          <String, Object?>{'role': 'user', 'content': 'classify'},
        ],
      ),
      throwsA(same(providerError)),
    );
  });

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

Future<Object?> _throwingTrace({
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
  throw StateError('trace failed');
}

class _FakeLlmBridge implements AgentRuntimeLlmBridge {
  _FakeLlmBridge({this.response = const <String, Object?>{}, this.error});

  final Map<String, Object?> response;
  final Object? error;

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
    final error = this.error;
    if (error != null) throw error;
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
