/// §4.6 W-D5 — on-device Vision ingest (user's own key, direct to the
/// provider; the original image never reaches our servers).
///
/// Implements the [CloudIngestClient] surface (the cloud Worker relay
/// was removed in W-D7), so the ingest pipeline is unchanged. It runs
/// the one-shot forced-tool parse locally via [DeviceLlmClient.complete]
/// using the verbatim-ported schema/prompt/extraction
/// (`device_vision_parse.dart`), then maps rows through the *shared*
/// `parsedTransactionFromWire` — so device and cloud yield identical
/// [ParsedTransaction]s for the same model JSON.
///
/// **Privacy-correct divergence from the chat failover (§4.6.4)**: a
/// device Vision failure is *not* retried on our cloud relay. The user
/// opted into "原图不经我方服务器"; silently re-sending the image to our
/// Worker would break exactly that promise. The error surfaces instead.
library;

import '../../../core/ai/runtime/device/anthropic/anthropic_client.dart';
import '../../../core/ai/runtime/device/anthropic/anthropic_wire.dart';
import '../../../core/ai/runtime/device/device_vision_parse.dart';
import '../../../core/auth/auth_session.dart';
import '../domain/ingest_models.dart';
import 'cloud_ingest_client.dart';

/// Mirrors the backend `VISION_MAX_TOKENS`.
const int _kVisionMaxTokens = 4096;

class DeviceVisionIngestClient implements CloudIngestClient {
  const DeviceVisionIngestClient({required DeviceLlmClient client})
    : _client = client;

  final DeviceLlmClient _client;

  @override
  Future<List<ParsedTransaction>> parse({
    required AuthSession session,
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
      throw CloudIngestException('端侧解析失败：${e.message}');
    }

    final List<Map<String, Object?>> rows;
    try {
      rows = extractVisionDraftRows(completion.content);
    } on VisionNoExtraction {
      throw CloudIngestException('未能从该文件解析出交易');
    }

    final out = <ParsedTransaction>[];
    for (final row in rows) {
      final parsed = parsedTransactionFromWire(row);
      if (parsed != null) out.add(parsed);
    }
    return out;
  }
}

/// Picks device-direct Vision when a usable on-device runtime exists,
/// else the Worker relay. No device→cloud failover (see library doc).
class RoutingCloudIngestClient implements CloudIngestClient {
  const RoutingCloudIngestClient({
    required CloudIngestClient cloud,
    CloudIngestClient? device,
  }) : _cloud = cloud,
       _device = device;

  final CloudIngestClient _cloud;
  final CloudIngestClient? _device;

  bool get usesDevice => _device != null;

  @override
  Future<List<ParsedTransaction>> parse({
    required AuthSession session,
    required IngestSourceKind kind,
    required String mime,
    required String contentBase64,
    String? currencyHint,
  }) {
    final client = _device ?? _cloud;
    return client.parse(
      session: session,
      kind: kind,
      mime: mime,
      contentBase64: contentBase64,
      currencyHint: currencyHint,
    );
  }
}
