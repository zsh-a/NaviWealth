import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/auth/providers.dart' as core_auth;
import '../../core/config/app_config.dart';
import '../../core/config/providers.dart';
import '../../core/logging/logging_crash_reporter.dart';
import '../../core/logging/providers.dart';
import '../../core/logging/sentry_crash_reporter.dart';
import '../../core/sync/providers.dart';
import '../../design_system/preferences/theme_preferences.dart';
import '../../features/auth/data/auth_controller.dart';
import '../../features/auth/data/auth_route_guard.dart';
import '../agent_runtime/overrides/agent_runtime_provider_overrides.dart';
import '../domain_composition.dart';
import '../routing/route_guard.dart';
import 'embedder_bootstrap.dart';

/// Builds the production provider graph without starting background work.
///
/// Keeping this list separate from `bootstrap.dart` makes the pre-frame path
/// explicit: constructing overrides is synchronous; providers remain lazy
/// until the UI or post-frame startup mounts them.
List<Override> buildBootstrapProviderOverrides({
  required AppConfig config,
  required SharedPreferences preferences,
  required bool sentryReady,
}) {
  return <Override>[
    appConfigProvider.overrideWithValue(config),
    sharedPreferencesProvider.overrideWithValue(preferences),
    if (sentryReady)
      crashReporterDelegateProvider.overrideWithValue(
        const SentryCrashReporter(),
      )
    else if (kDebugMode)
      crashReporterDelegateProvider.overrideWith(
        (ref) => LoggingCrashReporter(talker: ref.watch(talkerProvider)),
      ),
    routeGuardsProvider.overrideWith(
      (ref) => <RouteGuard>[
        if (!config.bypassAuth) ref.watch(authRouteGuardProvider),
        ref.watch(domainOptInRouteGuardProvider),
      ],
    ),
    ...agentRuntimeProviderOverrides(),
    syncAuthTokenProvider.overrideWith(
      (ref) =>
          () async => ref
              .read(authControllerProvider.notifier)
              .currentSession()
              ?.accessToken,
    ),
    core_auth.authSessionReaderProvider.overrideWith(
      (ref) =>
          () => ref.read(authControllerProvider.notifier).currentSession(),
    ),
    core_auth.authSessionProvider.overrideWith((ref) {
      final state = ref.watch(authControllerProvider).value;
      return state is AuthLoggedIn ? state.session : null;
    }),
    core_auth.authStateProvider.overrideWith(
      (ref) => ref.watch(authControllerProvider).value,
    ),
    core_auth.authOnUnauthorizedProvider.overrideWith(
      (ref) =>
          () => ref.read(authControllerProvider.notifier).refreshIfPossible(),
    ),
    core_auth.switchToLocalOnlyProvider.overrideWith(
      (ref) =>
          () => ref.read(authControllerProvider.notifier).switchToLocalOnly(),
    ),
    core_auth.domainOptInTokenRefreshProvider.overrideWith(
      (ref) => () async {
        await ref.read(authControllerProvider.notifier).refreshIfPossible();
      },
    ),
    ...lifeOsDomainCompositionOverrides(),
    lazyEmbedderProviderOverride(),
  ];
}
