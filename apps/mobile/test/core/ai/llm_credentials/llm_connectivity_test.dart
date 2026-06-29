import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/llm_credentials/llm_connectivity.dart';
import 'package:naviwealth/core/ai/llm_credentials/llm_credentials.dart';
import 'package:naviwealth/core/ai/runtime/device/anthropic/anthropic_client.dart';

LlmRequestException _e(int s, [String m = 'boom']) =>
    LlmRequestException(statusCode: s, message: m);

void main() {
  group('classifyLlmProbeException', () {
    test('401/403 → authFailed', () {
      expect(
        classifyLlmProbeException(_e(401)).status,
        LlmProbeStatus.authFailed,
      );
      expect(
        classifyLlmProbeException(_e(403)).status,
        LlmProbeStatus.authFailed,
      );
    });

    test('404 → notFound (bad base url)', () {
      expect(
        classifyLlmProbeException(_e(404)).status,
        LlmProbeStatus.notFound,
      );
    });

    test('429 → rateLimited and counts as reached', () {
      final r = classifyLlmProbeException(_e(429));
      expect(r.status, LlmProbeStatus.rateLimited);
      expect(r.reachedProvider, isTrue);
      expect(r.ok, isFalse);
    });

    test('400 → badRequest, surfaces provider message', () {
      final r = classifyLlmProbeException(_e(400, 'unknown model xyz'));
      expect(r.status, LlmProbeStatus.badRequest);
      expect(r.message, contains('unknown model xyz'));
      expect(r.reachedProvider, isTrue);
    });

    test('0 → network unreachable', () {
      final r = classifyLlmProbeException(_e(0, 'SocketException'));
      expect(r.status, LlmProbeStatus.network);
      expect(r.reachedProvider, isFalse);
    });

    test('other status → unknown with code', () {
      final r = classifyLlmProbeException(_e(503, 'maintenance'));
      expect(r.status, LlmProbeStatus.unknown);
      expect(r.message, contains('503'));
    });
  });

  group('LlmConnectivityProbe', () {
    test('keyless profile short-circuits without a network call', () async {
      // dioFactory throws if invoked → proves no request is attempted.
      final probe = DirectLlmConnectivityProbe(
        dioFactory: () => throw StateError('should not hit the network'),
      );
      const profile = LlmProfile(
        id: 'p',
        name: '',
        provider: LlmProvider.anthropic,
        apiKey: '   ',
      );
      final r = await probe.probe(profile);
      expect(r.status, LlmProbeStatus.authFailed);
      expect(r.ok, isFalse);
    });

    test('OpenAI profile probes via chat completions endpoint', () async {
      final adapter = _CaptureAdapter(
        jsonEncode({
          'choices': [
            {
              'message': {'role': 'assistant', 'content': 'ok'},
              'finish_reason': 'stop',
            },
          ],
        }),
      );
      final probe = DirectLlmConnectivityProbe(
        dioFactory: () => Dio()..httpClientAdapter = adapter,
      );
      const profile = LlmProfile(
        id: 'p',
        name: '',
        provider: LlmProvider.openai,
        apiKey: 'sk-openai',
        baseUrl: 'https://openai.test/v1',
        model: 'gpt-test',
      );

      final r = await probe.probe(profile);

      expect(r.status, LlmProbeStatus.ok);
      expect(
        adapter.calls.single.uri.toString(),
        'https://openai.test/v1/chat/completions',
      );
      expect(adapter.calls.single.headers['authorization'], 'Bearer sk-openai');
      final body = jsonDecode(adapter.body) as Map<String, Object?>;
      expect(body['model'], 'gpt-test');
      expect(body['stream'], false);
      expect(body['messages'], hasLength(1));
    });
  });
}

class _CaptureAdapter implements HttpClientAdapter {
  _CaptureAdapter(this.responseBody);

  final String responseBody;
  final List<RequestOptions> calls = [];
  String body = '';

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls.add(options);
    if (requestStream != null) {
      body = utf8.decode(
        (await requestStream.toList()).expand<int>((c) => c).toList(),
      );
    }
    return ResponseBody.fromString(
      responseBody,
      200,
      headers: const {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }
}
