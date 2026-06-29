/// On-device Vision ingest (user's own key, through the embedded FRB bridge to
/// the provider; the original image never reaches our servers).
///
/// Implements the shared [VisionIngestClient] surface, so the ingest pipeline
/// can choose FRB-backed Vision or an unavailable fallback. The legacy direct
/// [DeviceVisionIngestClient] is retained for compatibility, but production
/// wiring uses [FrbVisionIngestClient]. Both use the verbatim-ported
/// schema/prompt/extraction (`device_vision_parse.dart`), then map rows through
/// the *shared* `parsedTransactionFromWire` — so deterministic and Vision paths
/// share the same [ParsedTransaction] JSON semantics.
///
/// **Privacy-correct divergence from the chat failover (§4.6.4)**: a
/// device Vision failure is *not* retried on a cloud relay. The user
/// opted into "原图不经我方服务器"; silently re-sending the image to our
/// Worker would break exactly that promise. The error surfaces instead.
library;

import '../../../app/agent_runtime_llm_bridge.dart';
import '../../../core/ai/runtime/device/anthropic/anthropic_client.dart';
import '../../../core/ai/runtime/device/anthropic/anthropic_wire.dart';
import '../../../core/ai/runtime/device/device_vision_parse.dart';
import '../domain/ingest_models.dart';
import 'vision_ingest_client.dart';

/// Mirrors the backend `VISION_MAX_TOKENS`.
const int _kVisionMaxTokens = 4096;

class DeviceVisionIngestClient implements VisionIngestClient {
  const DeviceVisionIngestClient({required DeviceLlmClient client})
    : _client = client;

  final DeviceLlmClient _client;

  @override
  Future<List<ParsedTransaction>> parse({
    required IngestSourceKind kind,
    required String mime,
    required String contentBase64,
    String? currencyHint,
  }) async {
    final request = AnthropicRequest(
      model: _client.config.model,
      maxTokens: _kVisionMaxTokens,
      system: kVisionSystemPrompt,
      messages: buildVisionMessages(
        mime: mime,
        contentB64: contentBase64,
        currencyHint: currencyHint,
      ),
      tools: [visionParseToolSchema()],
      stream: false,
    );

    final AnthropicCompletion completion;
    try {
      completion = await _client.complete(request);
    } on LlmRequestException catch (e) {
      throw VisionIngestException('端侧解析失败：${e.message}');
    }

    final List<Map<String, Object?>> rows;
    try {
      rows = extractVisionDraftRows(completion.content);
    } on VisionNoExtraction {
      throw VisionIngestException('未能从该文件解析出交易');
    }

    final out = <ParsedTransaction>[];
    for (final row in rows) {
      final parsed = parsedTransactionFromWire(row);
      if (parsed != null) out.add(parsed);
    }
    return out;
  }
}

class FrbVisionIngestClient implements VisionIngestClient {
  const FrbVisionIngestClient({required AgentRuntimeLlmBridge llmBridge})
    : _llmBridge = llmBridge;

  final AgentRuntimeLlmBridge _llmBridge;

  @override
  Future<List<ParsedTransaction>> parse({
    required IngestSourceKind kind,
    required String mime,
    required String contentBase64,
    String? currencyHint,
  }) async {
    final tool = visionParseToolSchema();
    final messages = <Map<String, Object?>>[
      const <String, Object?>{'role': 'system', 'content': kVisionSystemPrompt},
      for (final message in buildVisionMessages(
        mime: mime,
        contentB64: contentBase64,
        currencyHint: currencyHint,
      ))
        message.toJson(),
    ];
    final tools = <Map<String, Object?>>[
      <String, Object?>{
        'name': tool.name,
        'description': tool.description,
        'input_schema': tool.inputSchema,
        'risk': 'read_only',
      },
    ];

    final Map<String, Object?> response;
    try {
      response = await _llmBridge.completeProfile(
        messages: messages,
        tools: tools,
        maxOutputTokens: _kVisionMaxTokens,
        metadata: const <String, Object?>{
          'surface': 'finance_vision_ingest',
          'agent_id': 'finance_vision_ingest',
        },
      );
    } on Object catch (e) {
      throw VisionIngestException('端侧解析失败：$e');
    }

    final content = _extractAnthropicContent(response);
    final List<Map<String, Object?>> rows;
    try {
      rows = extractVisionDraftRows(content);
    } on VisionNoExtraction {
      throw VisionIngestException('未能从该文件解析出交易');
    }

    final out = <ParsedTransaction>[];
    for (final row in rows) {
      final parsed = parsedTransactionFromWire(row);
      if (parsed != null) out.add(parsed);
    }
    return out;
  }

  static List<Object?> _extractAnthropicContent(Map<String, Object?> response) {
    final metadata = response['metadata'];
    final content = metadata is Map ? metadata['anthropic_content'] : null;
    if (content is List) return content;
    throw VisionIngestException('端侧解析失败：模型未返回可解析的工具结果');
  }
}

/// Picks FRB-backed Vision when a usable on-device profile bridge exists, else
/// the unavailable fallback. No device→cloud failover (see library doc).
class RoutingVisionIngestClient implements VisionIngestClient {
  const RoutingVisionIngestClient({
    required VisionIngestClient fallback,
    VisionIngestClient? device,
  }) : _fallback = fallback,
       _device = device;

  final VisionIngestClient _fallback;
  final VisionIngestClient? _device;

  bool get usesDevice => _device != null;

  @override
  Future<List<ParsedTransaction>> parse({
    required IngestSourceKind kind,
    required String mime,
    required String contentBase64,
    String? currencyHint,
  }) {
    final client = _device ?? _fallback;
    return client.parse(
      kind: kind,
      mime: mime,
      contentBase64: contentBase64,
      currencyHint: currencyHint,
    );
  }
}
