import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/llm_credentials/llm_connectivity.dart';
import 'package:naviwealth/core/ai/llm_credentials/llm_credentials.dart';

LlmProbeException _e(int s, [String m = 'boom']) =>
    LlmProbeException(statusCode: s, message: m);

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

  group('UnavailableLlmConnectivityProbe', () {
    test('fails closed without issuing provider requests', () async {
      const probe = UnavailableLlmConnectivityProbe();

      final r = await probe.probe(
        const LlmProfile(
          id: 'p',
          name: '',
          provider: LlmProvider.openai,
          apiKey: 'sk-openai',
        ),
      );

      expect(r.status, LlmProbeStatus.unknown);
      expect(r.ok, isFalse);
      expect(r.reachedProvider, isFalse);
    });
  });
}
