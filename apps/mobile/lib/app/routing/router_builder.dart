import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/domain_scope.dart';
import '../../core/lifeos/domain_pack.dart';
import '../../core/logging/providers.dart';
import '../../core/logging/talker_route_observer.dart';
import '../../core/shell/auth_route_paths.dart';
import '../../core/shell/deferred_route.dart';
import '../../core/shell/route_error_page.dart';
import '../../core/shell/settings_route_paths.dart';
import '../../design_system/widgets/system_back_scope.dart';
import '../../features/ai_chat/ui/ai_chat_page.dart' deferred as ai_chat_lib;
import '../../features/auth/ui/devices_page.dart' deferred as devices_lib;
import '../../features/auth/ui/login_page.dart';
import '../../features/auth/ui/onboarding_page.dart';
import '../../features/settings/ui/agents_settings_page.dart';
import '../../features/settings/ui/ai/ai_llm_credentials_page.dart';
import '../../features/settings/ui/ai/ai_models_page.dart';
import '../../features/settings/ui/ai/ai_privacy_page.dart';
import '../../features/settings/ui/ai/ai_transparency_page.dart';
import '../../features/settings/ui/backup/backup_page.dart';
import '../../features/settings/ui/data_management/data_management_page.dart';
import '../../features/settings/ui/domains_settings_page.dart';
import '../../features/settings/ui/log_viewer_page.dart';
import '../../features/settings/ui/notification_settings_page.dart';
import '../../features/settings/ui/perf_diagnostics_page.dart';
import '../../features/settings/ui/settings_page.dart' deferred as settings_lib;
import '../../features/settings/ui/sync/sync_status_page.dart';
import '../domain_packs.dart';
import '../shell/app_dock_shell.dart';
import 'route_analytics_observer.dart';
import 'route_guard.dart';

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
Future<void> preloadDeferredRoutesForTest({List<DomainPack>? packs}) async {
  final resolvedPacks = packs ?? kAllDomainPacks;
  await Future.wait<void>(<Future<void>>[
    for (final p in resolvedPacks)
      if (p.deferredPreloader != null) p.deferredPreloader!(),
    settings_lib.loadLibrary(),
    devices_lib.loadLibrary(),
    ai_chat_lib.loadLibrary(),
  ]);
}

/// Builds the app's [GoRouter].
///
/// IA structure (D-2.3b, Plan B multi-domain shell — see
/// `docs/architecture/lifeos-shell.md` §3):
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
        path: AuthRoutes.login,
        name: AuthRouteNames.login,
        builder: (context, state) =>
            const ExitConfirmingSystemBackScope(child: LoginPage()),
      ),
      GoRoute(
        path: AuthRoutes.onboarding,
        name: AuthRouteNames.onboarding,
        builder: (context, state) =>
            const ExitConfirmingSystemBackScope(child: OnboardingPage()),
      ),
      // Settings — global meta, accessed from Today's header gear. Lives
      // outside the dock shell so it covers the full canvas while open and
      // returns to whatever tab the user came from on pop.
      _settingsRoute(packs),
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
GoRoute _settingsRoute(List<DomainPack> packs) {
  return GoRoute(
    path: SettingsRoutes.root,
    name: SettingsRouteNames.root,
    builder: (context, state) => _backSafe(
      DeferredRoute(
        load: settings_lib.loadLibrary,
        builder: (_) => settings_lib.SettingsPage(),
      ),
    ),
    routes: [
      GoRoute(
        path: 'devices',
        name: SettingsRouteNames.devices,
        builder: (context, state) => _backSafe(
          DeferredRoute(
            load: devices_lib.loadLibrary,
            builder: (_) => devices_lib.DevicesPage(),
          ),
        ),
      ),
      GoRoute(
        path: 'backup',
        name: SettingsRouteNames.backup,
        builder: (context, state) => _backSafe(
          BackupPage(
            domain: DomainScope.tryParse(
              state.uri.queryParameters['domain'] ?? '',
            ),
          ),
        ),
      ),
      GoRoute(
        path: 'data-management',
        name: SettingsRouteNames.dataManagement,
        builder: (context, state) => _backSafe(const DataManagementPage()),
      ),
      GoRoute(
        path: 'notifications',
        name: SettingsRouteNames.notifications,
        builder: (context, state) =>
            _backSafe(const NotificationSettingsPage()),
      ),
      GoRoute(
        path: 'logs',
        name: SettingsRouteNames.logs,
        builder: (context, state) => _backSafe(const LogViewerPage()),
      ),
      GoRoute(
        path: 'performance',
        name: SettingsRouteNames.performance,
        builder: (context, state) => _backSafe(const PerfDiagnosticsPage()),
      ),
      GoRoute(
        path: 'sync',
        name: SettingsRouteNames.sync,
        builder: (context, state) => _backSafe(const SyncStatusPage()),
      ),
      GoRoute(
        path: 'domains',
        name: SettingsRouteNames.domains,
        builder: (context, state) => _backSafe(const DomainsSettingsPage()),
      ),
      ..._domainSettingsRoutes(packs),
      ..._domainOwnedSettingsRoutes(packs),
      GoRoute(
        path: 'ai-history',
        name: SettingsRouteNames.aiHistory,
        builder: (context, state) => _backSafe(
          DeferredRoute(
            load: ai_chat_lib.loadLibrary,
            builder: (_) => ai_chat_lib.AiChatPage(),
          ),
        ),
      ),
      GoRoute(
        path: 'ai-privacy',
        name: SettingsRouteNames.aiPrivacy,
        builder: (context, state) => _backSafe(const AiPrivacyPage()),
      ),
      GoRoute(
        path: 'ai-llm',
        name: SettingsRouteNames.aiLlm,
        builder: (context, state) => _backSafe(const AiLlmCredentialsPage()),
      ),
      GoRoute(
        path: 'ai-models',
        name: SettingsRouteNames.aiModels,
        builder: (context, state) => _backSafe(const AiModelsPage()),
      ),
      GoRoute(
        path: 'agents',
        name: SettingsRouteNames.agents,
        builder: (context, state) => _backSafe(const AgentsSettingsPage()),
      ),
      GoRoute(
        path: 'ai-transparency',
        name: SettingsRouteNames.aiTransparency,
        builder: (context, state) => _backSafe(const AiTransparencyPage()),
        routes: [
          GoRoute(
            path: ':requestId',
            name: SettingsRouteNames.aiTransparencyDetail,
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

List<RouteBase> _domainSettingsRoutes(List<DomainPack> packs) {
  return [
    for (final pack in packs)
      if (pack.settingsSpec?.routeBuilder case final routeBuilder?)
        routeBuilder(_backSafe),
  ];
}

List<RouteBase> _domainOwnedSettingsRoutes(List<DomainPack> packs) {
  return [
    for (final pack in packs)
      if (pack.settingsRoutesBuilder case final routesBuilder?)
        ...routesBuilder(_backSafe),
  ];
}

/// Wraps an out-of-shell settings page so the system back gesture routes
/// through [SystemBackScope] (pop → else go to the logical parent).
Widget _backSafe(Widget child) => SystemBackScope(child: child);

final appRouterProvider = Provider<GoRouter>((ref) => buildAppRouter(ref));
