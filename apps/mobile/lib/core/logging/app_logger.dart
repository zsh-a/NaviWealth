import 'package:logger/logger.dart';

import '../config/app_config.dart';
import 'crash_reporter.dart';

/// Thin wrapper over the `logger` package that:
///   * picks a verbosity per [AppEnvironment] (dev = trace, staging = info,
///     prod = warning),
///   * forwards `warning` and above to the registered [CrashReporter] so a
///     single call site emits both a console log and a crash breadcrumb,
///   * never throws — logging must not be load-bearing.
///
/// Construct one instance per app (see `loggerProvider`). Call
/// [AppLogger.bootstrap] at startup to install the global default used by code
/// paths that run before Riverpod is ready (e.g. zone error handlers).
class AppLogger {
  AppLogger({required AppEnvironment environment, CrashReporter? crashReporter})
    : _environment = environment,
      _crashReporter = crashReporter ?? const NoopCrashReporter(),
      _delegate = Logger(
        level: _levelFor(environment),
        filter: ProductionFilter(),
        printer: _printerFor(environment),
      );

  final AppEnvironment _environment;
  final CrashReporter _crashReporter;
  final Logger _delegate;

  AppEnvironment get environment => _environment;

  static AppLogger _instance = AppLogger(environment: AppEnvironment.dev);

  /// Globally accessible logger for code that runs before DI is set up.
  /// Inside the widget tree, prefer `ref.read(loggerProvider)`.
  static AppLogger get instance => _instance;

  /// Replace the global [instance] — call once during bootstrap.
  static void bootstrap(AppLogger logger) {
    _instance = logger;
  }

  void t(Object? message) => _delegate.t(message);

  void d(Object? message) => _delegate.d(message);

  void i(Object? message) => _delegate.i(message);

  void w(Object? message, {Object? error, StackTrace? stackTrace}) {
    _delegate.w(message, error: error, stackTrace: stackTrace);
    _crashReporter.recordBreadcrumb(
      message: '$message',
      level: BreadcrumbLevel.warning,
    );
  }

  void e(Object? message, {Object? error, StackTrace? stackTrace}) {
    _delegate.e(message, error: error, stackTrace: stackTrace);
    if (error != null) {
      _crashReporter.captureError(
        error,
        stackTrace: stackTrace,
        hint: '$message',
      );
    } else {
      _crashReporter.captureMessage('$message', level: BreadcrumbLevel.error);
    }
  }

  static Level _levelFor(AppEnvironment env) {
    switch (env) {
      case AppEnvironment.dev:
        return Level.trace;
      case AppEnvironment.staging:
        return Level.info;
      case AppEnvironment.prod:
        return Level.warning;
    }
  }

  static LogPrinter _printerFor(AppEnvironment env) {
    switch (env) {
      case AppEnvironment.dev:
        return PrettyPrinter(
          methodCount: 0,
          errorMethodCount: 8,
          lineLength: 100,
          colors: true,
          printEmojis: false,
          dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
        );
      case AppEnvironment.staging:
      case AppEnvironment.prod:
        return SimplePrinter(printTime: true, colors: false);
    }
  }
}
