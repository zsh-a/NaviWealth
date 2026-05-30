import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/lifeos/domain_pack.dart';
import '../core/logging/providers.dart';
import '../core/logging/talker_route_observer.dart';
import '../design_system/widgets/system_back_scope.dart';
import '../features/ai_chat/ui/ai_chat_page.dart' deferred as ai_chat_lib;
import '../features/auth/presentation/devices_page.dart'
    deferred as devices_lib;
import '../features/auth/presentation/login_page.dart';
import '../features/auth/presentation/onboarding_page.dart';
import '../features/settings/backup/backup_page.dart';
import '../features/settings/fx_rates/fx_rates_page.dart';
import '../features/settings/log_viewer_page.dart';
import '../features/settings/settings_page.dart' deferred as settings_lib;
import '../features/settings/ui/ai_llm_credentials_page.dart';
import '../features/settings/ui/ai_models_page.dart';
import '../features/settings/ui/ai_privacy_page.dart';
import '../features/settings/ui/ai_transparency_page.dart';
import '../features/settings/ui/domains_settings_page.dart';
import '../features/settings/ui/fire_stress_settings_page.dart';
import '../features/settings/ui/monthly_expense_settings_page.dart';
import '../features/settings/ui/risk_thresholds_page.dart';
import '../features/settings/ui/sync_status_page.dart';
import 'app_dock_shell.dart';
import 'deferred_route.dart';
import 'domain_packs.dart';
import 'route_analytics_observer.dart';
import 'route_error_page.dart';
import 'route_guard.dart';
import 'route_paths.dart';

/// Test-only: eagerly resolve every deferred-as library the router maps
/// to a tab so subsequent [DeferredRoute] mounts see an already-completed
/// `loadLibrary()` future. Without this, widget tests sit on the loading
/// spinner — `loadLibrary()` is real-async and the fake test clock can't
/// drive it. Call from `setUpAll` inside a `runAsync` block.
///
/// Iterates [packs] (defaults to [kAllDomainPacks]) plus the settings
/// tree's own deferred libs — each domain owns its own preloader (Plan B
/// isolation), so adding a new domain with deferred routes is a single
/// `deferredPreloader` field on its [DomainPack].
@visibleForTesting
Future<void> preloadDeferredRoutesForTest({
  List<DomainPack> packs = kAllDomainPacks,
}) async {
  await Future.wait<void>(<Future<void>>[
    for (final p in packs)
      if (p.deferredPreloader != null) p.deferredPreloader!(),
    settings_lib.loadLibrary(),
    devices_lib.loadLibrary(),
    ai_chat_lib.loadLibrary(),
  ]);
}

/// Builds the app's [GoRouter].
///
/// IA structure (D-2.3b, Plan B multi-domain shell — see
/// `docs/lifeos-shell.md` §3):
///
/// - Outer [ShellRoute] mounts [AppDockShell]: share-intent lifecycle,
///   AI route-context sync, root system-back handling, and the domain
///   dock chrome (visible only when ≥ 2 domains are registered).
/// - Each domain provides its own [StatefulShellRoute] under the dock
///   via [DomainPack.shellRouteBuilder]. Routes for every registered
///   pack mount unconditionally so deep links survive opt-in toggles;
///   the dock chrome already hides inactive domains.
/// - Settings, login, onboarding stay outside the dock shell — they
///   cover the full canvas while open and pop back into whatever
///   domain the user came from.
GoRouter buildAppRouter(Ref ref, {String initialLocation = '/'}) {
  final packs = ref.read(domainPackRegistryProvider);
  final shellRoutes = <RouteBase>[
    for (final p in packs)
      if (p.shellRouteBuilder != null) p.shellRouteBuilder!(),
  ];
  return GoRouter(
    initialLocation: initialLocation,
    observers: <NavigatorObserver>[
      ref.read(routeAnalyticsObserverProvider),
      TalkerRouteObserver(ref.read(talkerProvider)),
    ],
    refreshListenable: ref.read(routeRefreshListenableProvider),
    redirect: (context, state) => routerRedirect(ref.container, context, state),
    errorBuilder: (context, state) => RouteErrorPage(state: state),
    routes: [
      GoRoute(
        path: AppRoutes.login,
        name: AppRouteNames.login,
        builder: (context, state) => const LoginPage(),
      ),
      GoRoute(
        path: AppRoutes.onboarding,
        name: AppRouteNames.onboarding,
        builder: (context, state) => const OnboardingPage(),
      ),
      // Settings — global meta, accessed from Today's header gear. Lives
      // outside the dock shell so it covers the full canvas while open and
      // returns to whatever tab the user came from on pop.
      _settingsRoute(),
      // Multi-domain dock shell (D-2.3b). Wraps every per-domain
      // StatefulShellRoute so the dock chrome + global lifecycle hooks
      // stay mounted across domain switches. Skipped when no pack
      // contributed a route (defensive — `ShellRoute` asserts non-empty
      // `routes`; a domain-less test build should still boot).
      if (shellRoutes.isNotEmpty)
        ShellRoute(
          builder: (context, state, child) => AppDockShell(child: child),
          routes: shellRoutes,
        ),
    ],
  );
}

/// Top-level settings sub-tree. Outside the shell so opening Settings
/// covers the bottom nav and `pop` returns to whatever tab the user
/// came from. See IA contract §1: Settings is global meta, not a tab.
///
/// Because this sub-tree is a *sibling* of the dock shell, it does not
/// inherit the shell's root system-back handler. Every page is therefore
/// wrapped in [SystemBackScope] so the Android back gesture mirrors the
/// toolbar arrow (pop → else go to the logical parent) instead of falling
/// through to the OS and exiting the app when a settings route is the
/// stack root (reached via `go()` / deep link / app restore).
GoRoute _settingsRoute() {
  return GoRoute(
    path: AppRoutes.settings,
    name: AppRouteNames.settings,
    builder: (context, state) => _backSafe(
      DeferredRoute(
        load: settings_lib.loadLibrary,
        builder: (_) => settings_lib.SettingsPage(),
      ),
    ),
    routes: [
      GoRoute(
        path: 'devices',
        name: AppRouteNames.devices,
        builder: (context, state) => _backSafe(
          DeferredRoute(
            load: devices_lib.loadLibrary,
            builder: (_) => devices_lib.DevicesPage(),
          ),
        ),
      ),
      GoRoute(
        path: 'fx-rates',
        name: AppRouteNames.fxRates,
        builder: (context, state) => _backSafe(const FxRatesPage()),
      ),
      GoRoute(
        path: 'backup',
        name: AppRouteNames.backup,
        builder: (context, state) => _backSafe(const BackupPage()),
      ),
      GoRoute(
        path: 'logs',
        name: AppRouteNames.logs,
        builder: (context, state) => _backSafe(const LogViewerPage()),
      ),
      GoRoute(
        path: 'sync',
        name: AppRouteNames.sync,
        builder: (context, state) => _backSafe(const SyncStatusPage()),
      ),
      GoRoute(
        path: 'domains',
        name: AppRouteNames.domains,
        builder: (context, state) => _backSafe(const DomainsSettingsPage()),
      ),
      GoRoute(
        path: 'ai-history',
        name: AppRouteNames.aiHistory,
        builder: (context, state) => _backSafe(
          DeferredRoute(
            load: ai_chat_lib.loadLibrary,
            builder: (_) => ai_chat_lib.AiChatPage(),
          ),
        ),
      ),
      GoRoute(
        path: 'ai-privacy',
        name: AppRouteNames.aiPrivacy,
        builder: (context, state) => _backSafe(const AiPrivacyPage()),
      ),
      GoRoute(
        path: 'ai-llm',
        name: AppRouteNames.aiLlm,
        builder: (context, state) => _backSafe(const AiLlmCredentialsPage()),
      ),
      GoRoute(
        path: 'ai-models',
        name: AppRouteNames.aiModels,
        builder: (context, state) => _backSafe(const AiModelsPage()),
      ),
      GoRoute(
        path: 'risk-thresholds',
        name: AppRouteNames.riskThresholds,
        builder: (context, state) => _backSafe(const RiskThresholdsPage()),
      ),
      GoRoute(
        path: 'stress-test',
        name: AppRouteNames.stressTest,
        builder: (context, state) => _backSafe(const FireStressSettingsPage()),
      ),
      GoRoute(
        path: 'monthly-expense',
        name: AppRouteNames.monthlyExpense,
        builder: (context, state) =>
            _backSafe(const MonthlyExpenseSettingsPage()),
      ),
      GoRoute(
        path: 'ai-transparency',
        name: AppRouteNames.aiTransparency,
        builder: (context, state) => _backSafe(const AiTransparencyPage()),
        routes: [
          GoRoute(
            path: ':requestId',
            name: AppRouteNames.aiTransparencyDetail,
            builder: (context, state) => _backSafe(
              AiTransparencyDetailPage(
                requestId: state.pathParameters['requestId'] ?? '',
              ),
            ),
          ),
        ],
      ),
    ],
  );
}

/// Wraps an out-of-shell settings page so the system back gesture routes
/// through [SystemBackScope] (pop → else go to the logical parent).
Widget _backSafe(Widget child) => SystemBackScope(child: child);

final appRouterProvider = Provider<GoRouter>((ref) => buildAppRouter(ref));
