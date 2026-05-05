import 'package:talker/talker.dart';

import '../config/app_config.dart';
import 'crash_reporter.dart';

/// Thin wrapper over the `talker` package that:
///   * picks a verbosity per [AppEnvironment] (dev = verbose, staging = info,
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
      _talker = Talker(
        settings: TalkerSettings(
          useConsoleLogs: true,
          useHistory: true,
          maxHistoryItems: 1000,
          timeFormat: TimeFormat.timeAndSeconds,
        ),
      );

  final AppEnvironment _environment;
  final CrashReporter _crashReporter;
  final Talker _talker;

  AppEnvironment get environment => _environment;

  /// Expose the underlying [Talker] for downstream use (Dio interceptors,
  /// TalkerScreen, route observer).
  Talker get talker => _talker;

  static AppLogger _instance = AppLogger(environment: AppEnvironment.dev);

  /// Globally accessible logger for code that runs before DI is set up.
  /// Inside the widget tree, prefer `ref.read(loggerProvider)`.
  static AppLogger get instance => _instance;

  /// Replace the global [instance] — call once during bootstrap.
  static void bootstrap(AppLogger logger) {
    _instance = logger;
  }

  void t(Object? message) => _talker.verbose(message);

  void d(Object? message) => _talker.debug(message);

  void i(Object? message) => _talker.info(message);

  void w(Object? message, {Object? error, StackTrace? stackTrace}) {
    _talker.warning(message, error, stackTrace);
    _crashReporter.recordBreadcrumb(
      message: '$message',
      level: BreadcrumbLevel.warning,
    );
  }

  void e(Object? message, {Object? error, StackTrace? stackTrace}) {
    _talker.error(message, error, stackTrace);
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
}
