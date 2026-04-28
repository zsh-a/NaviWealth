import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

// Tabs other than home are split into their own dart2js part files; each part
// is loaded the first time the user navigates to that route. Home ships in
// main.dart.js to avoid a part-file fetch on first paint. See
// docs/web-bundle.md for the resulting bundle layout.
import '../features/accounts/account_form_page.dart';
import '../features/accounts/accounts_page.dart';
import '../features/analytics/analytics_page.dart' deferred as analytics_lib;
import '../features/assets/asset_detail_page.dart';
import '../features/assets/assets_page.dart' deferred as assets_lib;
import '../features/assets/cash_form_page.dart';
import '../features/assets/deposit_form_page.dart';
import '../features/assets/wealth_product_form_page.dart';
import '../features/home/home_page.dart';
import '../features/settings/settings_page.dart' deferred as settings_lib;
import '../l10n/gen/app_localizations.dart';
import 'deferred_route.dart';

/// Paths of the four primary tabs in the root shell, in display order.
///
/// The keyboard-shortcut layer (`core/shortcuts`) maps digits `1`-`4` to these
/// indexes — keep order in sync with `_RootShell`'s NavigationBar.
const List<String> kPrimaryTabPaths = <String>[
  '/',
  '/assets',
  '/analytics',
  '/settings',
];

/// Builds the app's [GoRouter]. Exposed (rather than inlined in the provider)
/// so tests can construct a router seeded at an arbitrary deep-link location.
GoRouter buildAppRouter({String initialLocation = '/'}) {
  return GoRouter(
    initialLocation: initialLocation,
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
            routes: [
              GoRoute(
                path: 'new/cash',
                name: 'asset-new-cash',
                builder: (context, state) => const CashFormPage(),
              ),
              GoRoute(
                path: 'new/deposit',
                name: 'asset-new-deposit',
                builder: (context, state) => const DepositFormPage(),
              ),
              GoRoute(
                path: 'new/wealth',
                name: 'asset-new-wealth',
                builder: (context, state) => const WealthProductFormPage(),
              ),
              GoRoute(
                path: ':assetId',
                name: 'asset-detail',
                builder: (context, state) =>
                    AssetDetailPage(assetId: state.pathParameters['assetId']!),
              ),
            ],
          ),
          GoRoute(
            path: '/accounts',
            name: 'accounts',
            builder: (context, state) => const AccountsPage(),
            routes: [
              GoRoute(
                path: 'new',
                name: 'account-new',
                builder: (context, state) => const AccountFormPage(),
              ),
              GoRoute(
                path: ':accountId',
                name: 'account-detail',
                builder: (context, state) => AccountFormPage(
                  accountId: state.pathParameters['accountId'],
                ),
              ),
            ],
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
}

final appRouterProvider = Provider<GoRouter>((ref) => buildAppRouter());

class _RootShell extends StatelessWidget {
  const _RootShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final location = GoRouter.of(
      context,
    ).routeInformationProvider.value.uri.path;
    // Sub-routes under `/assets` and `/accounts` keep the Assets tab
    // highlighted: e.g. `/assets/new/cash` is "still" assets-tab content.
    final int index;
    if (location.startsWith('/assets') || location.startsWith('/accounts')) {
      index = 1;
    } else if (location.startsWith('/analytics')) {
      index = 2;
    } else if (location.startsWith('/settings')) {
      index = 3;
    } else {
      index = 0;
    }
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
