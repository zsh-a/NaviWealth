import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/app/agent_runtime/bridges/agent_runtime_llm_bridge.dart';
import 'package:naviwealth/app/agent_runtime/bridges/agent_runtime_profile_completion_clients.dart';
import 'package:naviwealth/core/ai/contracts/contracts.dart';
import 'package:naviwealth/features/knowledge/data/knowledge_rewrite_client.dart';

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

  test('Knowledge rewrite uses the traced profile completion seam', () async {
    final records = <Map<String, Object?>>[];
    final bridge = _FakeLlmBridge(
      response: const <String, Object?>{
        'content': '',
        'object': <String, Object?>{
          'title': 'Clear 12 month plan',
          'body': 'See https://example.com.',
        },
      },
    );
    final client = FrbKnowledgeRewriteClient(
      llmBridge: bridge,
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

    final draft = await client.rewrite(
      const KnowledgeRewriteRequest(
        kind: KnowledgeRewriteKind.note,
        style: KnowledgeRewriteStyle.clear,
        objectId: 'note-1',
        locale: 'en',
        heading: '',
        content: 'See https://example.com.',
      ),
    );

    expect(draft.heading, 'Clear 12 month plan');
    expect(records.single['agent_id'], 'knowledge_rewrite');
    expect(records.single['domain'], 'knowledge');
    expect(records.single['surface'], 'knowledge_rewrite');
    expect(
      records.single['routing_reason'],
      kFrbAgentRuntimeProfileRoutingReason,
    );
    expect(records.single['error'], isNull);
    expect(bridge.lastMetadata?['object_type'], 'note');
    expect(bridge.lastMetadata?['rewrite_style'], 'clear');
    expect(bridge.lastResponseFormat, const <String, Object?>{
      'type': 'json_object',
    });
  });

  test('Knowledge rewrite traces local validation failures', () async {
    final records = <Map<String, Object?>>[];
    final response = <String, Object?>{
      'content': '',
      'object': <String, Object?>{
        'question': 'Invented question?',
        'rationale': 'Rationale',
      },
    };
    final client = FrbKnowledgeRewriteClient(
      llmBridge: _FakeLlmBridge(response: response),
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
              'response': llmResponse,
              'error': error,
            });
            return null;
          },
    );

    await expectLater(
      client.rewrite(
        const KnowledgeRewriteRequest(
          kind: KnowledgeRewriteKind.decision,
          style: KnowledgeRewriteStyle.clear,
          objectId: 'decision-invalid',
          locale: 'en',
          heading: '',
          content: 'Rationale',
        ),
      ),
      throwsFormatException,
    );

    expect(records, hasLength(1));
    expect(records.single['response'], same(response));
    expect(records.single['error'], isA<FormatException>());
  });

  test(
    'Knowledge rewrite reports an empty model completion explicitly',
    () async {
      final client = FrbKnowledgeRewriteClient(
        llmBridge: _FakeLlmBridge(
          response: const <String, Object?>{
            'content': '',
            'finish_reason': 'length',
          },
        ),
      );

      await expectLater(
        client.rewrite(
          const KnowledgeRewriteRequest(
            kind: KnowledgeRewriteKind.note,
            style: KnowledgeRewriteStyle.clear,
            objectId: 'note-empty',
            locale: 'en',
            heading: 'Title',
            content: 'Body',
          ),
        ),
        throwsA(
          isA<KnowledgeRewriteEmptyResponseException>().having(
            (error) => error.finishReason,
            'finishReason',
            'length',
          ),
        ),
      );
    },
  );

  test('Knowledge rewrite maps native empty structured output', () async {
    final client = FrbKnowledgeRewriteClient(
      llmBridge: _FakeLlmBridge(
        error: StateError(
          'structured_output_parse_failed: model response did not parse as '
          'JSON: EOF while parsing a value at line 1 column 0',
        ),
      ),
    );

    await expectLater(
      client.rewrite(
        const KnowledgeRewriteRequest(
          kind: KnowledgeRewriteKind.decision,
          style: KnowledgeRewriteStyle.structured,
          objectId: 'decision-empty',
          locale: 'en',
          heading: 'Choose?',
          content: 'Rationale',
        ),
      ),
      throwsA(isA<KnowledgeRewriteEmptyResponseException>()),
    );
  });
}

class _FakeLlmBridge implements AgentRuntimeLlmBridge {
  _FakeLlmBridge({this.response = const <String, Object?>{}, this.error});

  final Map<String, Object?> response;
  final Object? error;
  Map<String, Object?>? lastMetadata;
  Map<String, Object?>? lastResponseFormat;

  @override
  Map<String, Object?> buildRequest({
    required List<Map<String, Object?>> messages,
    List<Map<String, Object?>> tools = const <Map<String, Object?>>[],
    double? temperature,
    int? maxOutputTokens,
    Map<String, Object?>? responseFormat,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    return <String, Object?>{
      'messages': messages,
      'tools': tools,
      'response_format': ?responseFormat,
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
    Map<String, Object?>? responseFormat,
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
    Map<String, Object?>? responseFormat,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) async {
    lastMetadata = metadata;
    lastResponseFormat = responseFormat;
    if (error case final value?) throw value;
    return response;
  }

  @override
  Future<Map<String, Object?>> validateRequest({
    required List<Map<String, Object?>> messages,
    List<Map<String, Object?>> tools = const <Map<String, Object?>>[],
    double? temperature,
    int? maxOutputTokens,
    Map<String, Object?>? responseFormat,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    throw UnimplementedError();
  }
}
