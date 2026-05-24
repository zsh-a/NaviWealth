import 'package:talker/talker.dart';

import 'crash_reporter.dart';

/// [CrashReporter] that routes capture calls through a [Talker] instance
/// instead of shipping events to a remote service.
///
/// This is the **development-and-staging** sink: it proves the opt-in
/// pipeline end-to-end (preference flip → `crashReporterProvider` re-emits
/// → captureError actually surfaces somewhere) without taking on the
/// `sentry_flutter` dependency or requiring a DSN secret.
///
/// **Not a replacement for Sentry.** When the production Sentry wiring
/// lands it should override [crashReporterDelegateProvider] with a
/// `SentryCrashReporter`; this implementation stays around for dev runs
/// and tests where shipping telemetry would be wrong.
class LoggingCrashReporter extends CrashReporter {
  LoggingCrashReporter({required Talker talker}) : _talker = talker;

  final Talker _talker;

  @override
  void captureError(Object error, {StackTrace? stackTrace, String? hint}) {
    _talker.handle(
      error,
      stackTrace,
      hint == null ? 'crash_reporter: captureError' : 'crash_reporter: $hint',
    );
  }

  @override
  void captureMessage(
    String message, {
    BreadcrumbLevel level = BreadcrumbLevel.info,
  }) {
    switch (level) {
      case BreadcrumbLevel.debug:
        _talker.debug('crash_reporter: $message');
      case BreadcrumbLevel.info:
        _talker.info('crash_reporter: $message');
      case BreadcrumbLevel.warning:
        _talker.warning('crash_reporter: $message');
      case BreadcrumbLevel.error:
      case BreadcrumbLevel.fatal:
        _talker.error('crash_reporter: $message');
    }
  }

  @override
  void recordBreadcrumb({
    required String message,
    BreadcrumbLevel level = BreadcrumbLevel.info,
    String? category,
  }) {
    final tag = category == null ? 'breadcrumb' : 'breadcrumb/$category';
    _talker.verbose('$tag: $message');
  }

  @override
  void identifyUser({String? userId}) {
    _talker.verbose('crash_reporter: identify user=$userId');
  }
}
