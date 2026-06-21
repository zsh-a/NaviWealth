import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/config/app_config.dart';

void main() {
  group('AppConfig.sentryDsn', () {
    test('defaults to empty so unconfigured builds stay opt-out', () {
      // The dev build has no SENTRY_DSN dart-define set in `flutter test`,
      // so the default-value branch should win and report no DSN.
      expect(AppConfig.dev.sentryDsn, isEmpty);
      expect(AppConfig.dev.hasSentryDsn, isFalse);
    });

    test('hasSentryDsn flips on once a DSN is supplied', () {
      const config = AppConfig(
        apiBaseUrl: 'http://localhost:8787',
        environment: AppEnvironment.staging,
        sentryDsn: 'https://abc@o0.ingest.sentry.io/0',
      );
      expect(config.hasSentryDsn, isTrue);
    });
  });

  group('AppConfig native updates', () {
    test('stay disabled unless both latest version and URL are supplied', () {
      expect(AppConfig.dev.latestNativeVersion, isEmpty);
      expect(AppConfig.dev.nativeUpdateUrl, isEmpty);
      expect(AppConfig.dev.hasNativeUpdateTarget, isFalse);
    });

    test('enable once a version and distribution URL are supplied', () {
      const config = AppConfig(
        apiBaseUrl: 'http://localhost:8787',
        environment: AppEnvironment.staging,
        latestNativeVersion: '0.8.0',
        nativeUpdateUrl: 'https://example.com/download',
      );
      expect(config.hasNativeUpdateTarget, isTrue);
    });
  });
}
