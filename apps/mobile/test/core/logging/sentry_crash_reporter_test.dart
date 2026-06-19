import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/config/app_config.dart';
import 'package:naviwealth/core/logging/crash_reporter.dart';
import 'package:naviwealth/core/logging/sentry_crash_reporter.dart';
import 'package:sentry_flutter/sentry_flutter.dart' as sentry;

class _RecordingSentryClient implements SentryCrashReporterClient {
  final exceptions = <({Object error, StackTrace? stackTrace, String? hint})>[];
  final messages = <({String message, sentry.SentryLevel level})>[];
  final breadcrumbs =
      <({String message, sentry.SentryLevel level, String? category})>[];
  final users = <String?>[];

  @override
  void captureException(Object error, {StackTrace? stackTrace, String? hint}) {
    exceptions.add((error: error, stackTrace: stackTrace, hint: hint));
  }

  @override
  void captureMessage(String message, {required sentry.SentryLevel level}) {
    messages.add((message: message, level: level));
  }

  @override
  void addBreadcrumb({
    required String message,
    required sentry.SentryLevel level,
    String? category,
  }) {
    breadcrumbs.add((message: message, level: level, category: category));
  }

  @override
  void setUser(String? userId) {
    users.add(userId);
  }
}

class _ThrowingSentryClient implements SentryCrashReporterClient {
  Never _throw() => throw StateError('client failed');

  @override
  void captureException(Object error, {StackTrace? stackTrace, String? hint}) =>
      _throw();

  @override
  void captureMessage(String message, {required sentry.SentryLevel level}) =>
      _throw();

  @override
  void addBreadcrumb({
    required String message,
    required sentry.SentryLevel level,
    String? category,
  }) => _throw();

  @override
  void setUser(String? userId) => _throw();
}

void main() {
  group('initializeSentryCrashReporter', () {
    test('does nothing when no DSN is configured', () async {
      const config = AppConfig(
        apiBaseUrl: 'http://localhost:8787',
        environment: AppEnvironment.dev,
      );

      expect(await initializeSentryCrashReporter(config), isFalse);
    });
  });

  group('SentryCrashReporter', () {
    test('forwards errors, breadcrumbs, messages, and user identity', () {
      final client = _RecordingSentryClient();
      final reporter = SentryCrashReporter(client: client);
      final stack = StackTrace.current;

      reporter.captureError(
        StateError('boom'),
        stackTrace: stack,
        hint: 'save',
      );
      reporter.recordBreadcrumb(
        message: 'opened cashflow',
        level: BreadcrumbLevel.warning,
        category: 'navigation',
      );
      reporter.captureMessage('sync stalled', level: BreadcrumbLevel.error);
      reporter.identifyUser(userId: 'u-1');
      reporter.identifyUser();

      expect(client.exceptions.single.error, isA<StateError>());
      expect(client.exceptions.single.stackTrace, same(stack));
      expect(client.exceptions.single.hint, 'save');
      expect(client.breadcrumbs.single.message, 'opened cashflow');
      expect(client.breadcrumbs.single.level, sentry.SentryLevel.warning);
      expect(client.breadcrumbs.single.category, 'navigation');
      expect(client.messages.single.message, 'sync stalled');
      expect(client.messages.single.level, sentry.SentryLevel.error);
      expect(client.users, ['u-1', null]);
    });

    test('maps every BreadcrumbLevel to the matching SentryLevel', () {
      final client = _RecordingSentryClient();
      final reporter = SentryCrashReporter(client: client);

      for (final level in BreadcrumbLevel.values) {
        reporter.captureMessage(level.name, level: level);
      }

      expect(client.messages.map((m) => m.level).toList(), [
        sentry.SentryLevel.debug,
        sentry.SentryLevel.info,
        sentry.SentryLevel.warning,
        sentry.SentryLevel.error,
        sentry.SentryLevel.fatal,
      ]);
    });

    test('never throws when the underlying client fails', () {
      final reporter = SentryCrashReporter(client: _ThrowingSentryClient());

      expect(() => reporter.captureError(StateError('boom')), returnsNormally);
      expect(() => reporter.captureMessage('message'), returnsNormally);
      expect(
        () => reporter.recordBreadcrumb(message: 'crumb'),
        returnsNormally,
      );
      expect(() => reporter.identifyUser(userId: 'u-1'), returnsNormally);
    });
  });
}
