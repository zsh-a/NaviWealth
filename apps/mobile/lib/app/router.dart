import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

// Tabs other than home are split into their own dart2js part files; each part
// is loaded the first time the user navigates to that route. Home ships in
// main.dart.js to avoid a part-file fetch on first paint. See
// docs/web-bundle.md for the resulting bundle layout.
import '../features/analytics/analytics_page.dart' deferred as analytics_lib;
import '../features/assets/assets_page.dart' deferred as assets_lib;
import '../features/home/home_page.dart';
import '../features/settings/settings_page.dart' deferred as settings_lib;
import '../l10n/gen/app_localizations.dart';
import 'deferred_route.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      ShellRoute(
        builder: (context, state, child) => _RootShell(child: child),
        routes: [
          GoRoute(
            path: '/',
            name: 'home',
            builder: (context, state) => const HomePage(),
          ),
          GoRoute(
            path: '/assets',
            name: 'assets',
            builder: (context, state) => DeferredRoute(
              load: assets_lib.loadLibrary,
              builder: (_) => assets_lib.AssetsPage(),
            ),
          ),
          GoRoute(
            path: '/analytics',
            name: 'analytics',
            builder: (context, state) => DeferredRoute(
              load: analytics_lib.loadLibrary,
              builder: (_) => analytics_lib.AnalyticsPage(),
            ),
          ),
          GoRoute(
            path: '/settings',
            name: 'settings',
            builder: (context, state) => DeferredRoute(
              load: settings_lib.loadLibrary,
              builder: (_) => settings_lib.SettingsPage(),
            ),
          ),
        ],
      ),
    ],
  );
});

class _RootShell extends StatelessWidget {
  const _RootShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final location = GoRouter.of(
      context,
    ).routeInformationProvider.value.uri.path;
    final index = switch (location) {
      '/' => 0,
      '/assets' => 1,
      '/analytics' => 2,
      '/settings' => 3,
      _ => 0,
    };
    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.dashboard_outlined),
            selectedIcon: const Icon(Icons.dashboard),
            label: l10n.navHome,
          ),
          NavigationDestination(
            icon: const Icon(Icons.account_balance_wallet_outlined),
            selectedIcon: const Icon(Icons.account_balance_wallet),
            label: l10n.navAssets,
          ),
          NavigationDestination(
            icon: const Icon(Icons.pie_chart_outline),
            selectedIcon: const Icon(Icons.pie_chart),
            label: l10n.navAnalytics,
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: const Icon(Icons.settings),
            label: l10n.navSettings,
          ),
        ],
        onDestinationSelected: (i) {
          switch (i) {
            case 0:
              context.goNamed('home');
            case 1:
              context.goNamed('assets');
            case 2:
              context.goNamed('analytics');
            case 3:
              context.goNamed('settings');
          }
        },
      ),
    );
  }
}
