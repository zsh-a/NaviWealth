import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/config/app_config.dart';
import 'package:naviwealth/core/logging/app_logger.dart';
import 'package:naviwealth/core/logging/crash_reporter.dart';

class _RecordingCrashReporter extends CrashReporter {
  final List<({Object error, StackTrace? stack, String? hint})> errors = [];
  final List<({String message, BreadcrumbLevel level})> messages = [];
  final List<({String message, BreadcrumbLevel level, String? category})>
  breadcrumbs = [];

  @override
  void captureError(Object error, {StackTrace? stackTrace, String? hint}) {
    errors.add((error: error, stack: stackTrace, hint: hint));
  }

  @override
  void captureMessage(
    String message, {
    BreadcrumbLevel level = BreadcrumbLevel.info,
  }) {
    messages.add((message: message, level: level));
  }

  @override
  void recordBreadcrumb({
    required String message,
    BreadcrumbLevel level = BreadcrumbLevel.info,
    String? category,
  }) {
    breadcrumbs.add((message: message, level: level, category: category));
  }

  @override
  void identifyUser({String? userId}) {}
}

void main() {
  group('AppLogger crash forwarding', () {
    late _RecordingCrashReporter reporter;
    late AppLogger logger;

    setUp(() {
      reporter = _RecordingCrashReporter();
      logger = AppLogger(
        environment: AppEnvironment.dev,
        crashReporter: reporter,
      );
    });

    test('w() records a warning breadcrumb', () {
      logger.w('something looked off');
      expect(reporter.breadcrumbs, hasLength(1));
      expect(reporter.breadcrumbs.first.level, BreadcrumbLevel.warning);
      expect(reporter.breadcrumbs.first.message, contains('something'));
    });

    test('e() with error captures the error', () {
      final err = StateError('boom');
      logger.e('oops', error: err, stackTrace: StackTrace.current);
      expect(reporter.errors, hasLength(1));
      expect(reporter.errors.first.error, same(err));
      expect(reporter.errors.first.hint, contains('oops'));
    });

    test('e() without error captures a message at error level', () {
      logger.e('orphan error message');
      expect(reporter.errors, isEmpty);
      expect(reporter.messages, hasLength(1));
      expect(reporter.messages.first.level, BreadcrumbLevel.error);
    });

    test('debug logs do not reach the crash reporter', () {
      logger.d('dev only');
      logger.t('trace');
      logger.i('info');
      expect(reporter.errors, isEmpty);
      expect(reporter.messages, isEmpty);
      expect(reporter.breadcrumbs, isEmpty);
    });
  });

  test('environment is exposed for downstream consumers', () {
    final logger = AppLogger(environment: AppEnvironment.prod);
    expect(logger.environment, AppEnvironment.prod);
  });

  test('structured events retain safe fields and drop business data', () {
    final reporter = _RecordingCrashReporter();
    final logger = AppLogger(
      environment: AppEnvironment.dev,
      crashReporter: reporter,
    );

    logger.event(
      'finance.trade.submit.failed',
      operationId: 'op-1',
      level: AppLogLevel.error,
      fields: const {
        'stage': 'prepare',
        'error_code': 'timeout',
        'retryable': true,
        'account_id': 'private-account',
        'amount': 999,
      },
      error: StateError('AAPL 100 shares'),
    );

    final message = logger.talker.history.last.message!;
    expect(message, contains('finance.trade.submit.failed'));
    expect(message, contains('"operation_id":"op-1"'));
    expect(message, contains('"error_code":"timeout"'));
    expect(message, isNot(contains('private-account')));
    expect(message, isNot(contains('999')));
    expect(message, isNot(contains('AAPL')));
    expect(reporter.errors.single.error, isA<DiagnosticLogError>());
  });

  test('operation emits slow-stage and one terminal event', () async {
    final logger = AppLogger(environment: AppEnvironment.dev);
    final operation = logger.startOperation(
      'form.submit',
      operationId: 'op-2',
      fields: const {'form_type': 'expense'},
    );

    await operation.step(
      'commit',
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
      slowThreshold: const Duration(milliseconds: 5),
    );
    operation.complete();
    operation.complete(outcome: 'duplicate');

    final messages = logger.talker.history
        .map((entry) => entry.message ?? '')
        .join('\n');
    expect(messages, contains('form.submit.stage.slow'));
    expect(messages, contains('form.submit.stage.completed'));
    expect(
      RegExp(r'"event":"form\.submit\.completed"').allMatches(messages).length,
      1,
    );
  });

  test('diagnostic export redacts credentials and email addresses', () {
    final output = sanitizeDiagnosticExport(
      'Authorization: Bearer abc.def token=secret user@example.com',
    );

    expect(output, contains('Bearer <redacted>'));
    expect(output, contains('token=<redacted>'));
    expect(output, contains('<redacted-email>'));
    expect(output, isNot(contains('secret')));
    expect(output, isNot(contains('user@example.com')));
  });
}
