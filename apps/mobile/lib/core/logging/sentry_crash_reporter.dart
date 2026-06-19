import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart' as sentry;

import '../config/app_config.dart';
import 'crash_reporter.dart';

/// Initialise the Sentry SDK when the build supplies a DSN.
///
/// Empty DSN keeps the app on [NoopCrashReporter]. This preserves the
/// local-first default: crash telemetry is impossible unless the build is
/// configured with `--dart-define=SENTRY_DSN=...` and the user has opted in
/// through [OptInCrashReporter].
Future<bool> initializeSentryCrashReporter(AppConfig config) async {
  if (!config.hasSentryDsn) return false;
  try {
    await sentry.SentryFlutter.init((options) {
      options
        ..dsn = config.sentryDsn
        ..environment = config.environment.name
        ..sendDefaultPii = false
        ..attachScreenshot = false
        ..diagnosticLevel = sentry.SentryLevel.warning
        ..debug = kDebugMode;
      // No tracing by default. Finance data is sensitive and issue capture is
      // the narrow scope of the opt-in crash reporter.
      options.tracesSampleRate = null;
    });
    return true;
  } on Object catch (error, stackTrace) {
    debugPrint('Sentry initialization failed: $error\n$stackTrace');
    return false;
  }
}

abstract interface class SentryCrashReporterClient {
  FutureOr<void> captureException(
    Object error, {
    StackTrace? stackTrace,
    String? hint,
  });

  FutureOr<void> captureMessage(
    String message, {
    required sentry.SentryLevel level,
  });

  FutureOr<void> addBreadcrumb({
    required String message,
    required sentry.SentryLevel level,
    String? category,
  });

  FutureOr<void> setUser(String? userId);
}

class StaticSentryCrashReporterClient implements SentryCrashReporterClient {
  const StaticSentryCrashReporterClient();

  @override
  Future<void> captureException(
    Object error, {
    StackTrace? stackTrace,
    String? hint,
  }) async {
    if (hint != null && hint.isNotEmpty) {
      await sentry.Sentry.addBreadcrumb(
        sentry.Breadcrumb(
          message: hint,
          category: 'capture_hint',
          level: sentry.SentryLevel.info,
        ),
      );
    }
    await sentry.Sentry.captureException(error, stackTrace: stackTrace);
  }

  @override
  Future<void> captureMessage(
    String message, {
    required sentry.SentryLevel level,
  }) async {
    await sentry.Sentry.captureMessage(message, level: level);
  }

  @override
  Future<void> addBreadcrumb({
    required String message,
    required sentry.SentryLevel level,
    String? category,
  }) async {
    await sentry.Sentry.addBreadcrumb(
      sentry.Breadcrumb(
        message: message,
        category: category ?? 'app',
        level: level,
      ),
    );
  }

  @override
  Future<void> setUser(String? userId) async {
    final result = sentry.Sentry.configureScope(
      (scope) =>
          scope.setUser(userId == null ? null : sentry.SentryUser(id: userId)),
    );
    if (result is Future<void>) await result;
  }
}

class SentryCrashReporter extends CrashReporter {
  const SentryCrashReporter({
    SentryCrashReporterClient client = const StaticSentryCrashReporterClient(),
  }) : _client = client;

  final SentryCrashReporterClient _client;

  @override
  void captureError(Object error, {StackTrace? stackTrace, String? hint}) {
    _run(
      () => _client.captureException(error, stackTrace: stackTrace, hint: hint),
    );
  }

  @override
  void captureMessage(
    String message, {
    BreadcrumbLevel level = BreadcrumbLevel.info,
  }) {
    _run(() => _client.captureMessage(message, level: _toSentryLevel(level)));
  }

  @override
  void recordBreadcrumb({
    required String message,
    BreadcrumbLevel level = BreadcrumbLevel.info,
    String? category,
  }) {
    _run(
      () => _client.addBreadcrumb(
        message: message,
        level: _toSentryLevel(level),
        category: category,
      ),
    );
  }

  @override
  void identifyUser({String? userId}) {
    _run(() => _client.setUser(userId));
  }

  void _run(FutureOr<void> Function() action) {
    try {
      final result = action();
      if (result is Future<void>) {
        unawaited(result.catchError((_) {}));
      }
    } on Object {
      // Logging must never become load-bearing.
    }
  }
}

sentry.SentryLevel _toSentryLevel(BreadcrumbLevel level) {
  switch (level) {
    case BreadcrumbLevel.debug:
      return sentry.SentryLevel.debug;
    case BreadcrumbLevel.info:
      return sentry.SentryLevel.info;
    case BreadcrumbLevel.warning:
      return sentry.SentryLevel.warning;
    case BreadcrumbLevel.error:
      return sentry.SentryLevel.error;
    case BreadcrumbLevel.fatal:
      return sentry.SentryLevel.fatal;
  }
}
