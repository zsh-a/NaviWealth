import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/app/agent_runtime_llm_bridge.dart';
import 'package:naviwealth/core/ai/runtime/device/device_vision_parse.dart';
import 'package:naviwealth/features/ingest/data/device_ingest_client.dart';
import 'package:naviwealth/features/ingest/data/vision_ingest_client.dart';
import 'package:naviwealth/features/ingest/domain/ingest_models.dart';

class _FakeIngest implements VisionIngestClient {
  _FakeIngest(this.tag);
  final String tag;
  bool called = false;
  @override
  Future<List<ParsedTransaction>> parse({
    required IngestSourceKind kind,
    required String mime,
    required String contentBase64,
    String? currencyHint,
  }) async {
    called = true;
    return [
      ParsedTransaction(
        description: tag,
        amountMinor: -100,
        currency: 'USD',
        occurredAt: DateTime.utc(2026),
        confidence: 0.6,
      ),
    ];
  }
}

void main() {
  group('device_vision_parse — ported from parse.rs', () {
    test('tool schema requires the core fields', () {
      final s = visionParseToolSchema();
      expect(s.name, kVisionEmitTool);
      final req =
          ((s.inputSchema['properties'] as Map)['transactions'] as Map)['items']
              as Map;
      expect(
        (req['required'] as List).cast<String>(),
        containsAll(['amount_minor', 'occurred_at', 'currency']),
      );
    });

    test('PDF → document block, image otherwise; hint injected', () {
      final pdf = buildVisionMessages(
        mime: 'application/pdf',
        contentB64: 'Qkk=',
        currencyHint: 'CNY',
      );
      final pdfContent = pdf.single.content! as List;
      expect((pdfContent[0] as Map)['type'], 'document');
      expect((pdfContent[1] as Map)['text'], contains('CNY'));

      final img = buildVisionMessages(mime: 'image/png', contentB64: 'Qkk=');
      final imgContent = img.single.content! as List;
      expect((imgContent[0] as Map)['type'], 'image');
      expect(
        ((imgContent[0] as Map)['source'] as Map)['media_type'],
        'image/png',
      );

      final blank = buildVisionMessages(mime: '  ', contentB64: 'Qkk=');
      expect(
        (((blank.single.content! as List)[0] as Map)['source']
            as Map)['media_type'],
        'application/octet-stream',
      );
    });

    test('extracts rows from the forced tool call', () {
      final rows = extractVisionDraftRows([
        {'type': 'text', 'text': 'ignored'},
        {
          'type': 'tool_use',
          'name': kVisionEmitTool,
          'input': {
            'transactions': [
              {
                'description': 'Starbucks',
                'amount_minor': -3800,
                'currency': 'cny',
                'occurred_at': '2026-05-10',
                'category_hint': 'coffee',
              },
            ],
          },
        },
      ]);
      expect(rows, hasLength(1));
      // shared mapper → identical to the provider-Vision path's output
      final tx = parsedTransactionFromWire(rows.single)!;
      expect(tx.description, 'Starbucks');
      expect(tx.amountMinor, -3800); // expense-negative preserved
      expect(tx.currency, 'CNY'); // upper-cased
      expect(tx.occurredAt, DateTime.utc(2026, 5, 10));
      expect(tx.categoryHint, 'coffee');
    });

    test('empty list is valid; missing tool throws VisionNoExtraction', () {
      expect(
        extractVisionDraftRows([
          {
            'type': 'tool_use',
            'name': kVisionEmitTool,
            'input': {'transactions': <Object?>[]},
          },
        ]),
        isEmpty,
      );
      expect(
        () => extractVisionDraftRows([
          {'type': 'text', 'text': 'I cannot read this'},
        ]),
        throwsA(isA<VisionNoExtraction>()),
      );
    });

    test('caps at kVisionMaxParsedDrafts and skips non-map rows', () {
      final many = [
        for (var i = 0; i < kVisionMaxParsedDrafts + 50; i++)
          {
            'description': 'r$i',
            'amount_minor': -1,
            'currency': 'USD',
            'occurred_at': '2026-01-01',
          },
        'not-a-map',
      ];
      final rows = extractVisionDraftRows([
        {
          'type': 'tool_use',
          'name': kVisionEmitTool,
          'input': {'transactions': many},
        },
      ]);
      expect(rows, hasLength(kVisionMaxParsedDrafts));
    });
  });

  group('RoutingVisionIngestClient (W-D5)', () {
    test('device present → device used, fallback untouched', () async {
      final fallback = _FakeIngest('fallback');
      final device = _FakeIngest('device');
      final r = RoutingVisionIngestClient(fallback: fallback, device: device);
      expect(r.usesDevice, isTrue);
      final out = await r.parse(
        kind: IngestSourceKind.receiptImage,
        mime: 'image/png',
        contentBase64: 'Qkk=',
      );
      expect(device.called, isTrue);
      expect(fallback.called, isFalse);
      expect(out.single.description, 'device');
    });

    test('no device → unavailable fallback used', () async {
      final fallback = _FakeIngest('fallback');
      final r = RoutingVisionIngestClient(fallback: fallback);
      expect(r.usesDevice, isFalse);
      final out = await r.parse(
        kind: IngestSourceKind.statementPdf,
        mime: 'application/pdf',
        contentBase64: 'Qkk=',
      );
      expect(fallback.called, isTrue);
      expect(out.single.description, 'fallback');
    });
  });

  group('FrbVisionIngestClient', () {
    test(
      'sends multimodal content and parses raw Anthropic tool_use blocks',
      () async {
        final bridge = _FakeLlmBridge(
          anthropicContent: [
            {
              'type': 'tool_use',
              'name': kVisionEmitTool,
              'input': {
                'transactions': [
                  {
                    'description': 'Coffee',
                    'amount_minor': -450,
                    'currency': 'usd',
                    'occurred_at': '2026-06-01',
                  },
                ],
              },
            },
          ],
        );
        final client = FrbVisionIngestClient(llmBridge: bridge);

        final rows = await client.parse(
          kind: IngestSourceKind.receiptImage,
          mime: 'image/png',
          contentBase64: 'ZmFrZQ==',
          currencyHint: 'USD',
        );

        expect(bridge.calls, 1);
        expect(bridge.lastMessages.first['role'], 'system');
        final userContent = bridge.lastMessages.last['content']! as List;
        expect((userContent.first as Map)['type'], 'image');
        expect(bridge.lastTools.single['name'], kVisionEmitTool);
        expect(bridge.lastTools.single['risk'], 'read_only');
        expect(bridge.lastMetadata['surface'], 'finance_vision_ingest');
        expect(rows.single.description, 'Coffee');
        expect(rows.single.amountMinor, -450);
        expect(rows.single.currency, 'USD');
        expect(rows.single.occurredAt, DateTime.utc(2026, 6, 1));
      },
    );

    test(
      'throws a user-facing ingest error when FRB has no tool_use block',
      () {
        final client = FrbVisionIngestClient(
          llmBridge: _FakeLlmBridge(anthropicContent: const <Object?>[]),
        );

        expect(
          () => client.parse(
            kind: IngestSourceKind.receiptImage,
            mime: 'image/png',
            contentBase64: 'ZmFrZQ==',
          ),
          throwsA(isA<VisionIngestException>()),
        );
      },
    );
  });
}

class _FakeLlmBridge implements AgentRuntimeLlmBridge {
  _FakeLlmBridge({required this.anthropicContent});

  final List<Object?> anthropicContent;
  var calls = 0;
  List<Map<String, Object?>> lastMessages = const <Map<String, Object?>>[];
  List<Map<String, Object?>> lastTools = const <Map<String, Object?>>[];
  Map<String, Object?> lastMetadata = const <String, Object?>{};

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
      'max_output_tokens': maxOutputTokens,
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
  }) async {
    return <String, Object?>{'content': responseText};
  }

  @override
  Future<Map<String, Object?>> completeProfile({
    required List<Map<String, Object?>> messages,
    List<Map<String, Object?>> tools = const <Map<String, Object?>>[],
    double? temperature,
    int? maxOutputTokens,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) async {
    calls += 1;
    lastMessages = messages;
    lastTools = tools;
    lastMetadata = metadata;
    return <String, Object?>{
      'provider': 'mock',
      'model': 'test-model',
      'content': '',
      'metadata': <String, Object?>{'anthropic_content': anthropicContent},
    };
  }

  @override
  Future<Map<String, Object?>> validateRequest({
    required List<Map<String, Object?>> messages,
    List<Map<String, Object?>> tools = const <Map<String, Object?>>[],
    double? temperature,
    int? maxOutputTokens,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) async {
    return buildRequest(
      messages: messages,
      tools: tools,
      temperature: temperature,
      maxOutputTokens: maxOutputTokens,
      metadata: metadata,
    );
  }
}
