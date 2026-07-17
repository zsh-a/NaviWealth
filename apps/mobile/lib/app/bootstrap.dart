import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/config/app_config.dart';
import '../core/format/formatters.dart';
import '../core/logging/app_logger.dart';
import '../core/logging/providers.dart';
import '../core/logging/sentry_crash_reporter.dart';
import '../core/perf/providers.dart';
import 'bootstrap/bootstrap_provider_overrides.dart';

/// Initializes the app shell: framework binding, URL strategy, and the global
/// error pipeline (Flutter framework errors, async zone errors, and the
/// platform dispatcher channel) all funnel through [AppLogger] → [CrashReporter].
///
/// Returns a [ProviderContainer] pre-seeded with the bootstrap logger and warm
/// preferences. Authentication, network diagnostics, Memory Runtime, native
/// model discovery, sync, and domain background work start after first paint.
Future<ProviderContainer> bootstrap({AppConfig? config}) async {
  final started = Stopwatch()..start();
  WidgetsFlutterBinding.ensureInitialized();
  // Clean URLs on web (e.g. /portfolio instead of /#/portfolio).
  // No-op elsewhere.
  usePathUrlStrategy();
  final effectiveConfig = config ?? AppConfig.dev;
  // These independent critical prerequisites run concurrently. Preferences
  // and formatter data are needed by the first widget build; Sentry must be
  // ready before the global error handlers are installed.
  final preferencesFuture = SharedPreferences.getInstance();
  final formattersFuture = AppFormatters.ensureInitialized();
  final sentryFuture = initializeSentryCrashReporter(effectiveConfig);
  final preferences = await preferencesFuture;
  await formattersFuture;
  final sentryReady = await sentryFuture;

  final container = ProviderContainer(
    // Riverpod 3 retries failed async providers by default, which can keep
    // `.future` consumers in loading indefinitely. Business retries are
    // explicit (user Retry, sync backoff, provider-specific policy).
    retry: (_, _) => null,
    overrides: buildBootstrapProviderOverrides(
      config: effectiveConfig,
      preferences: preferences,
      sentryReady: sentryReady,
    ),
  );
  // Force eager creation so AppLogger.instance is ready before any error
  // handler fires.
  final logger = container.read(loggerProvider);
  // Eager-init the frame timing collector so the addTimingsCallback
  // subscription is in place before the first frame ships. Otherwise
  // PerfTraceRecorder windows opened at startup would race the first
  // few frames and miss them. `roadmap-next.md` §4 M-5.
  container.read(frameTimingCollectorProvider);

  FlutterError.onError = (details) {
    if (isBenignDuplicateKeyDownAssertion(details)) {
      logger.w(
        'Ignored duplicate platform KeyDown assertion',
        error: details.exception,
        stackTrace: details.stack,
      );
      return;
    }
    logger.e(
      'Uncaught Flutter framework error',
      error: details.exception,
      stackTrace: details.stack,
    );
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    logger.e('Uncaught platform error', error: error, stackTrace: stack);
    return true;
  };

  logger.i(
    'NaviWealth critical bootstrap complete '
    '(${logger.environment.name}, elapsedMs=${started.elapsedMilliseconds})',
  );
  if (kDebugMode) {
    logger.i('API_BASE_URL: ${effectiveConfig.apiBaseUrl}');
  }

  return container;
}

/// Flutter can occasionally receive a duplicate platform KeyDown without an
/// intervening KeyUp, most often around OS/browser shortcuts or focus changes.
/// The framework asserts before app-level Shortcuts/Focus handlers run, so the
/// app cannot prevent the event. Treat that specific debug assertion as
/// non-fatal while leaving all other framework errors on the normal crash path.
@visibleForTesting
bool isBenignDuplicateKeyDownAssertion(FlutterErrorDetails details) {
  final text = details.exception.toString();
  return text.contains('hardware_keyboard.dart') &&
      text.contains('A KeyDownEvent is dispatched') &&
      text.contains('physical key is already pressed');
}

/// Runs [body] inside a guarded zone so async errors bubble to [AppLogger].
/// Use this from `main()` to wrap `runApp(...)`.
Future<void> runGuarded(Future<void> Function() body) async {
  await runZonedGuarded(body, (error, stack) {
    AppLogger.instance.e(
      'Uncaught zone error',
      error: error,
      stackTrace: stack,
    );
  });
}
