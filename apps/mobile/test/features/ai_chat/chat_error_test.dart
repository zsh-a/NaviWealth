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
}
