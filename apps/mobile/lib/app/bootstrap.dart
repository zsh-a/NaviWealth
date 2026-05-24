import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/auth/providers.dart' as core_auth;
import '../core/config/app_config.dart';
import '../core/format/formatters.dart';
import '../core/logging/app_logger.dart';
import '../core/logging/crash_reporter.dart';
import '../core/logging/logging_crash_reporter.dart';
import '../core/logging/providers.dart';
import '../core/perf/providers.dart';
import '../core/sync/providers.dart';
import '../data/market/sync/price_sync_providers.dart';
import '../design_system/preferences/theme_preferences.dart';
import '../features/auth/data/auth_controller.dart';
import '../features/auth/data/auth_route_guard.dart';
import '../features/cashflow/data/recurring_transaction_providers.dart';
import 'memory_indexers_bootstrap.dart';
import 'route_guard.dart';

/// Initializes the app shell: framework binding, URL strategy, and the global
/// error pipeline (Flutter framework errors, async zone errors, and the
/// platform dispatcher channel) all funnel through [AppLogger] → [CrashReporter].
///
/// Returns a [ProviderContainer] pre-seeded with the bootstrap logger and a
/// warm [SharedPreferences] handle so theme/market-color preferences resolve
/// synchronously on first build. The caller hosts it inside
/// `UncontrolledProviderScope`.
Future<ProviderContainer> bootstrap({AppConfig? config}) async {
  WidgetsFlutterBinding.ensureInitialized();
  // Clean URLs on web (e.g. /portfolio instead of /#/portfolio).
  // No-op elsewhere.
  usePathUrlStrategy();
  await AppFormatters.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  final effectiveConfig = config ?? AppConfig.dev;

  final container = ProviderContainer(
    overrides: [
      if (config != null) appConfigProvider.overrideWithValue(config),
      sharedPreferencesProvider.overrideWithValue(prefs),
      // `roadmap-next.md` §3.6 — in debug builds, route captureError /
      // recordBreadcrumb through TalkerScreen via [LoggingCrashReporter]
      // so engineers see the opt-in pipeline fire end-to-end without
      // taking on the `sentry_flutter` dependency. Release builds keep
      // the [NoopCrashReporter] default until the Sentry SDK lands; the
      // opt-in gate (`crashReportingEnabledProvider`) still wraps both.
      if (kDebugMode)
        crashReporterDelegateProvider.overrideWith(
          (ref) => LoggingCrashReporter(talker: ref.watch(talkerProvider)),
        ),
      // Plug the AuthRouteGuard into FIR-15's empty default. The guard
      // reads `authControllerProvider` per redirect; auth state changes
      // bump `routeRedirectVersionProvider` which makes go_router re-run
      // the full redirect chain. Skipped when `bypassAuth` is on so dev
      // builds can browse the app without a session.
      if (!effectiveConfig.bypassAuth)
        routeGuardsProvider.overrideWith(
          (ref) => <RouteGuard>[ref.watch(authRouteGuardProvider)],
        ),
      // Feed the access token to the SyncEngine so /sync/push and
      // /sync/pull go out authed once a session is active. The fetcher
      // closes over Riverpod's container, so token rotation is picked up
      // on every request without re-creating the SyncEngine.
      syncAuthTokenProvider.overrideWith(
        (ref) =>
            () async => ref
                .read(authControllerProvider.notifier)
                .currentSession()
                ?.accessToken,
      ),
      // Wire the AuthInterceptor's hooks to the live controller so any
      // future `authedDioProvider` consumer (feature endpoints that need
      // refresh-on-401) gets the correct session + recovery behaviour.
      core_auth.authSessionReaderProvider.overrideWith(
        (ref) =>
            () => ref.read(authControllerProvider.notifier).currentSession(),
      ),
      core_auth.authSessionProvider.overrideWith((ref) {
        final state = ref.watch(authControllerProvider).value;
        return state is AuthLoggedIn ? state.session : null;
      }),
      core_auth.authOnUnauthorizedProvider.overrideWith(
        (ref) =>
            () => ref.read(authControllerProvider.notifier).refreshIfPossible(),
      ),
    ],
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

  if (kDebugMode) {
    logger.i('NaviWealth bootstrap complete (${logger.environment.name})');
    logger.i('API_BASE_URL: ${effectiveConfig.apiBaseUrl}');

    // Network connectivity diagnostic
    final testDio = Dio(
      BaseOptions(
        baseUrl: effectiveConfig.apiBaseUrl,
        connectTimeout: const Duration(seconds: 5),
      ),
    );
    try {
      final resp = await testDio.get<dynamic>('/health');
      logger.i('Backend health check: ${resp.statusCode} ${resp.data}');
    } on DioException catch (e) {
      logger.e(
        'Backend health check FAILED',
        error: e,
        stackTrace: StackTrace.current,
      );
      logger.e('  type: ${e.type}');
      logger.e('  message: ${e.message}');
      logger.e('  error: ${e.error}');
    }
  }

  // Restore the persisted auth session before bootstrapping foreground sync
  // and startup jobs. Otherwise those jobs can observe the transient
  // "unknown" auth state and fail before the controller has read storage.
  if (!effectiveConfig.bypassAuth) {
    await container.read(authControllerProvider.future);
  }

  // Start foreground data sync. PriceSyncCoordinator owns both quote
  // warming and FX refresh so dashboard valuations have one startup path.
  container.read(syncSchedulerBootstrapProvider);
  container.read(priceSyncCoordinatorBootstrapProvider);
  // Eager-bind Memory Layer indexers (`docs/lifeos-shell.md` §6, D-1.7).
  // Reading this provider subscribes the trade-journal indexer (and any
  // future domain indexers) to their source streams so semantic memory
  // stays current without UI involvement.
  container.read(memoryLayerBootstrapProvider);
  if (container.read(core_auth.authSessionProvider) != null) {
    unawaited(
      container.read(
        recurringMaterialiseDueProvider(DateTime.now().toUtc()).future,
      ),
    );
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
