import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:talker/talker.dart';

import '../config/app_config.dart';
import 'app_logger.dart';
import 'crash_reporter.dart';

/// Active app config. Override at the root `ProviderScope` to switch envs
/// in flavor builds (e.g. staging entrypoint).
final appConfigProvider = Provider<AppConfig>((ref) => AppConfig.dev);

/// Crash reporter binding. The default is the no-op sink; the Sentry
/// integration task overrides this provider with a real reporter.
final crashReporterProvider = Provider<CrashReporter>(
  (ref) => const NoopCrashReporter(),
);

/// Application logger. Forwards `warning`+ events to [crashReporterProvider].
final loggerProvider = Provider<AppLogger>((ref) {
  final logger = AppLogger(
    environment: ref.watch(appConfigProvider).environment,
    crashReporter: ref.watch(crashReporterProvider),
  );
  AppLogger.bootstrap(logger);
  return logger;
});

/// Exposes the underlying [Talker] instance for downstream consumers
/// (Dio interceptors, TalkerScreen, route observer).
final talkerProvider = Provider<Talker>((ref) {
  return ref.watch(loggerProvider).talker;
});
