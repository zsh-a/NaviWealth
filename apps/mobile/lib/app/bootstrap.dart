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
import '../core/logging/providers.dart';
import '../core/sync/providers.dart';
import '../data/repositories/providers.dart';
import '../design_system/preferences/theme_preferences.dart';
import '../features/auth/data/auth_controller.dart';
import '../features/auth/data/auth_route_guard.dart';
import '../features/settings/data/base_currency_preference.dart';
import '../features/settings/fx_rates/providers.dart';
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

  FlutterError.onError = (details) {
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

  // Fire-and-forget FX rate sync on app launch. Errors are logged but
  // don't block startup — the dashboard degrades gracefully with a
  // "currency mismatch" banner when rates are missing.
  container.read(syncSchedulerBootstrapProvider);
  unawaited(_syncFxRates(container, logger));

  return container;
}

/// Trigger FX rate sync in the background. Reads the user's base currency
/// and account currencies, then fetches today's rates from Yahoo Finance.
///
/// Uses the repository directly instead of [accountsStreamProvider] because
/// the stream is `autoDispose` and has no listeners during bootstrap.
Future<void> _syncFxRates(ProviderContainer container, AppLogger logger) async {
  try {
    logger.i('FX rate sync: starting...');
    final service = await container.read(fxRateSyncServiceProvider.future);
    final base = container.read(baseCurrencyProvider);
    final accountRepo = await container.read(accountRepositoryProvider.future);
    final accounts = await accountRepo.listActive();
    final currencies = accounts.map((a) => a.currency).toSet();
    logger.i('FX rate sync: base=$base, currencies=$currencies');
    if (currencies.isEmpty ||
        (currencies.length == 1 && currencies.contains(base))) {
      logger.i('FX rate sync: no foreign currencies, skipping');
      return;
    }
    final synced = await service.syncRates(
      baseCurrency: base,
      accountCurrencies: currencies,
    );
    logger.i('FX rate sync complete: $synced pairs updated');
  } catch (e, st) {
    logger.w('FX rate sync failed (non-fatal)', error: e, stackTrace: st);
  }
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
