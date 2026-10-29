import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/ai_chat/domain/chat_error.dart';

void main() {
  test(
    'classifies provider authentication failures without exposing details',
    () {
      expect(
        chatErrorPresentationKey(
          code: 'provider_http_401',
          message: 'invalid api key: sk-secret',
        ),
        kChatErrorAuthentication,
      );
      expect(isChatConfigurationError(kChatErrorAuthentication), isTrue);
    },
  );

  test(
    'classifies retryable provider failures separately from configuration',
    () {
      expect(
        chatErrorPresentationKey(
          code: 'rate_limited',
          message: 'too many requests',
        ),
        kChatErrorRateLimited,
      );
      expect(isChatConfigurationError(kChatErrorRateLimited), isFalse);
    },
  );

  test('classifies wrapped provider failures from their diagnostic text', () {
    expect(
      chatErrorPresentationKey(
        code: 'frb_chat_error',
        message: 'ChatError(provider_http_503): upstream unavailable',
      ),
      kChatErrorNetwork,
    );
    expect(
      chatErrorPresentationKey(
        code: 'frb_chat_error',
        message: 'ChatError: invalid API key',
      ),
      kChatErrorAuthentication,
    );
  });

  test('keeps unknown diagnostics available for transparency', () {
    const message = 'unexpected provider detail';
    expect(
      chatErrorPresentationKey(code: 'unknown_code', message: message),
      message,
    );
  });

  test('wrapped native transport failures keep a network repair path', () {
    for (final message in [
      'error sending request for url (https://provider.example/v1/chat/completions)',
      'HTTP 502: Bad Gateway',
      'HTTP 503: service unavailable',
      'request timed out',
      'provider_request_failed: client error',
      'provider_body_read_failed: error decoding response body',
      'provider_stream_read_failed: stream reset',
    ]) {
      expect(
        chatErrorPresentationKey(code: 'frb_chat_error', message: message),
        kChatErrorNetwork,
        reason: message,
      );
    }
  });

  test('distinguishes silent connections from active but stalled or long responses', () {
    for (final entry in {
      'provider_first_response_timeout': kChatErrorFirstResponseTimeout,
      'provider_first_byte_timeout': kChatErrorFirstResponseTimeout,
      'provider_read_idle_timeout': kChatErrorReadIdleTimeout,
      'provider_model_progress_timeout': kChatErrorModelProgressTimeout,
      'provider_total_timeout': kChatErrorTotalTimeout,
    }.entries) {
      final key = chatErrorPresentationKey(
        code: 'frb_chat_error',
        message: '${entry.key}: timed out',
      );
      expect(key, entry.value);
      expect(isChatConfigurationError(key), isFalse);
    }
  });
}
