import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:talker/talker.dart';

import '../config/app_config.dart';
import 'app_logger.dart';
import 'crash_reporter.dart';
import 'crash_reporting_preference.dart';

/// Active app config. Override at the root `ProviderScope` to switch envs
/// in flavor builds (e.g. staging entrypoint).
final appConfigProvider = Provider<AppConfig>((ref) => AppConfig.dev);

/// Underlying crash reporter implementation. Defaults to [NoopCrashReporter];
/// the Sentry wiring task overrides this with a real sink. Direct consumers
/// should prefer [crashReporterProvider] so the user's opt-in preference
/// gates uploads in one place.
final crashReporterDelegateProvider = Provider<CrashReporter>(
  (ref) => const NoopCrashReporter(),
);

/// Crash reporter binding visible to the rest of the app. Wraps
/// [crashReporterDelegateProvider] in an [OptInCrashReporter] that drops
/// every event unless the user has explicitly turned crash reporting on
/// in Settings (`roadmap-next.md` §3.6). The opt-in default is OFF.
///
/// Falls back to the raw delegate when [crashReportingEnabledProvider]
/// is unreachable (e.g. tests that never override [sharedPreferencesProvider]).
/// The delegate itself defaults to [NoopCrashReporter], so the fallback
/// is a safe no-op in every environment — the only place that loses the
/// opt-in gate is integration tests that aren't actually wired to Sentry.
final crashReporterProvider = Provider<CrashReporter>((ref) {
  final delegate = ref.watch(crashReporterDelegateProvider);
  bool enabled;
  try {
    enabled = ref.watch(crashReportingEnabledProvider);
  } catch (_) {
    enabled = false;
  }
  return OptInCrashReporter(delegate: delegate, enabled: enabled);
});

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
