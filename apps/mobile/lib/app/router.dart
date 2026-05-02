import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../design_system/design_system.dart';

// Tabs other than home are split into their own dart2js part files; each part
// is loaded the first time the user navigates to that route. Home ships in
// main.dart.js to avoid a part-file fetch on first paint. See
// docs/web-bundle.md for the resulting bundle layout.
import '../features/accounts/account_form_page.dart';
import '../features/accounts/accounts_page.dart';
import '../features/ai_chat/state/route_context_provider.dart';
import '../features/ai_chat/ui/ai_chat_page.dart' deferred as ai_chat_lib;
import '../features/ai_chat/ui/ai_chat_sheet.dart';
import '../features/ai_chat/ui/ai_floating_pill.dart';
import '../features/analytics/analytics_page.dart' deferred as analytics_lib;
import '../features/assets/asset_detail_page.dart';
import '../features/assets/assets_page.dart' deferred as assets_lib;
import '../features/assets/cash_form_page.dart';
import '../features/assets/deposit_form_page.dart';
import '../features/assets/physical/ui/physical_asset_detail_page.dart'
    deferred as physical_detail_lib;
import '../features/assets/wealth_product_form_page.dart';
import '../features/auth/presentation/devices_page.dart'
    deferred as devices_lib;
import '../features/auth/presentation/login_page.dart';
import '../features/expense/ui/expense_categories_page.dart';
import '../features/expense/ui/expense_form_page.dart';
import '../features/expense/ui/expense_list_page.dart';
import '../features/expense/ui/expense_report_page.dart';
import '../features/fire/presentation/fire_page.dart' deferred as fire_lib;
import '../features/home/home_page.dart';
import '../features/investment/presentation/corporate_action_entry_route.dart'
    deferred as corp_action_lib;
import '../features/investment/presentation/trade_entry_form_page.dart';
import '../features/investment/presentation/transactions_list_page.dart';
import '../features/liabilities/ui/liabilities_page.dart'
    deferred as liabilities_lib;
import '../features/liabilities/ui/liability_detail_page.dart'
    deferred as liability_detail_lib;
import '../features/rebalance/ui/rebalance_page.dart' deferred as rebalance_lib;
import '../features/settings/fx_rates/fx_rates_page.dart';
import '../features/settings/settings_page.dart' deferred as settings_lib;
import '../l10n/gen/app_localizations.dart';
import 'deferred_route.dart';
import 'desktop_sidebar.dart';
import 'page_transitions.dart';
import 'route_analytics_observer.dart';
import 'route_error_page.dart';
import 'route_guard.dart';
import 'shell_preferences.dart';

/// Paths of the six primary tabs in the root shell, in display order.
///
/// The keyboard-shortcut layer (`core/shortcuts`) maps digits `1`-`6` to these
/// indexes — keep order in sync with `_RootShell`'s NavigationBar.
const List<String> kPrimaryTabPaths = <String>[
  '/',
  '/assets',
  '/expenses',
  '/analytics',
  '/fire',
  '/settings',
];

/// Test-only: eagerly resolve every deferred-as library the router maps to
/// a tab so subsequent [DeferredRoute] mounts see an already-completed
/// `loadLibrary()` future. Without this, widget tests sit on the loading
/// spinner — `loadLibrary()` is real-async and the fake test clock can't
/// drive it. Call from `setUpAll` inside a `runAsync` block.
@visibleForTesting
Future<void> preloadDeferredRoutesForTest() async {
  await Future.wait<void>(<Future<void>>[
    assets_lib.loadLibrary(),
    analytics_lib.loadLibrary(),
    settings_lib.loadLibrary(),
    fire_lib.loadLibrary(),
    liabilities_lib.loadLibrary(),
    liability_detail_lib.loadLibrary(),
    physical_detail_lib.loadLibrary(),
    corp_action_lib.loadLibrary(),
    devices_lib.loadLibrary(),
    rebalance_lib.loadLibrary(),
    ai_chat_lib.loadLibrary(),
  ]);
}

/// Builds the app's [GoRouter]. Exposed (rather than inlined in the provider)
/// so tests can construct a router seeded at an arbitrary deep-link location
/// and inject their own observers / guards through the [Ref].
GoRouter buildAppRouter(Ref ref, {String initialLocation = '/'}) {
  return GoRouter(
    initialLocation: initialLocation,
    observers: <NavigatorObserver>[ref.read(routeAnalyticsObserverProvider)],
    refreshListenable: ref.read(routeRefreshListenableProvider),
    redirect: (context, state) => routerRedirect(ref.container, context, state),
    errorBuilder: (context, state) => RouteErrorPage(state: state),
    routes: [
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (context, state) => const LoginPage(),
      ),
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
                path: 'corporate-action',
                name: 'corporate-action',
                builder: (context, state) => DeferredRoute(
                  load: corp_action_lib.loadLibrary,
                  builder: (_) => corp_action_lib.CorporateActionEntryRoute(),
                ),
              ),
              GoRoute(
                path: 'trade',
                name: 'trade-entry',
                pageBuilder: (context, state) {
                  final assetId = state.uri.queryParameters['assetId'];
                  final accountId = state.uri.queryParameters['accountId'];
                  return buildHeroAwareTransitionPage<void>(
                    context: context,
                    state: state,
                    child: TradeEntryFormPage(
                      assetId: assetId,
                      accountId: accountId,
                    ),
                  );
                },
              ),
              GoRoute(
                path: 'physical/:id',
                name: 'physicalAssetDetail',
                builder: (context, state) {
                  final id = state.pathParameters['id']!;
                  return DeferredRoute(
                    load: physical_detail_lib.loadLibrary,
                    builder: (_) =>
                        physical_detail_lib.PhysicalAssetDetailPage(id: id),
                  );
                },
              ),
              GoRoute(
                path: 'liabilities',
                name: 'liabilities',
                builder: (context, state) => DeferredRoute(
                  load: liabilities_lib.loadLibrary,
                  builder: (_) => liabilities_lib.LiabilitiesPage(),
                ),
                routes: [
                  GoRoute(
                    path: ':id',
                    name: 'liabilityDetail',
                    builder: (context, state) {
                      final id = state.pathParameters['id']!;
                      return DeferredRoute(
                        load: liability_detail_lib.loadLibrary,
                        builder: (_) =>
                            liability_detail_lib.LiabilityDetailPage(id: id),
                      );
                    },
                  ),
                ],
              ),
              GoRoute(
                path: ':assetId',
                name: 'asset-detail',
                pageBuilder: (context, state) => buildHeroAwareTransitionPage<void>(
                  context: context,
                  state: state,
                  child: AssetDetailPage(
                    assetId: state.pathParameters['assetId']!,
                  ),
                ),
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
                pageBuilder: (context, state) => buildHeroAwareTransitionPage<void>(
                  context: context,
                  state: state,
                  child: AccountFormPage(
                    accountId: state.pathParameters['accountId'],
                  ),
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/transactions',
            name: 'transactions',
            builder: (context, state) => const TransactionsListPage(),
          ),
          GoRoute(
            path: '/expenses',
            name: 'expenses',
            builder: (context, state) => const ExpenseListPage(),
            routes: [
              GoRoute(
                path: 'new',
                name: 'expense-new',
                builder: (context, state) => const ExpenseFormPage(),
              ),
              GoRoute(
                path: 'categories',
                name: 'expense-categories',
                builder: (context, state) => const ExpenseCategoriesPage(),
              ),
              GoRoute(
                path: 'report',
                name: 'expense-report',
                builder: (context, state) => const ExpenseReportPage(),
              ),
              GoRoute(
                path: ':expenseId',
                name: 'expense-detail',
                builder: (context, state) => ExpenseFormPage(
                  expenseId: state.pathParameters['expenseId'],
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
            path: '/fire',
            name: 'fire',
            builder: (context, state) => DeferredRoute(
              load: fire_lib.loadLibrary,
              builder: (_) => fire_lib.FirePage(),
            ),
          ),
          GoRoute(
            path: '/rebalance',
            name: 'rebalance',
            builder: (context, state) => DeferredRoute(
              load: rebalance_lib.loadLibrary,
              builder: (_) => rebalance_lib.RebalancePage(),
            ),
          ),
          GoRoute(
            path: '/ai',
            name: 'ai-chat',
            builder: (context, state) => DeferredRoute(
              load: ai_chat_lib.loadLibrary,
              builder: (_) => ai_chat_lib.AiChatPage(),
            ),
          ),
          GoRoute(
            path: '/settings',
            name: 'settings',
            builder: (context, state) => DeferredRoute(
              load: settings_lib.loadLibrary,
              builder: (_) => settings_lib.SettingsPage(),
            ),
            routes: [
              GoRoute(
                path: 'devices',
                name: 'devices',
                builder: (context, state) => DeferredRoute(
                  load: devices_lib.loadLibrary,
                  builder: (_) => devices_lib.DevicesPage(),
                ),
              ),
              GoRoute(
                path: 'fx-rates',
                name: 'fx-rates',
                builder: (context, state) => const FxRatesPage(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

final appRouterProvider = Provider<GoRouter>((ref) => buildAppRouter(ref));

class _RootShell extends ConsumerWidget {
  const _RootShell({required this.child});

  final Widget child;

  // Breakpoints mirror docs/design/01-responsive-layout.md. 1240 keeps a
  // ≥720dp content column next to a ~256dp permanent drawer; 900 is where
  // the rail has room to show its labels inline.
  static const double _tabletBreakpoint = 600;
  static const double _desktopBreakpoint = 1240;
  static const double _railExtendedBreakpoint = 900;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final location = GoRouter.of(
      context,
    ).routeInformationProvider.value.uri.path;

    // Keep the route context provider in sync with navigation.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(aiRouteContextProvider.notifier).state = AiRouteContext(
        path: location,
      );
    });
    // Sub-routes under `/assets` and `/accounts` keep the Assets tab
    // highlighted: e.g. `/assets/new/cash` is "still" assets-tab content.
    final int index;
    if (location.startsWith('/assets') || location.startsWith('/accounts')) {
      index = 1;
    } else if (location.startsWith('/expenses')) {
      index = 2;
    } else if (location.startsWith('/analytics')) {
      index = 3;
    } else if (location.startsWith('/fire')) {
      index = 4;
    } else if (location.startsWith('/settings')) {
      index = 5;
    } else {
      index = 0;
    }
    final destinations = _navDestinations(l10n);
    void onSelected(int i) {
      if (i < 0 || i >= kPrimaryTabPaths.length) return;
      context.go(kPrimaryTabPaths[i]);
    }

    final showPill = !location.startsWith('/ai');

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final isDesktop = width >= _desktopBreakpoint;

        Widget shell;
        if (isDesktop) {
          shell = _DesktopShell(
            destinations: destinations,
            selectedIndex: index,
            onDestinationSelected: onSelected,
            child: child,
          );
        } else if (width >= _tabletBreakpoint) {
          shell = _TabletShell(
            destinations: destinations,
            selectedIndex: index,
            onDestinationSelected: onSelected,
            extended: width >= _railExtendedBreakpoint,
            child: child,
          );
        } else {
          shell = _MobileShell(
            destinations: destinations,
            selectedIndex: index,
            onDestinationSelected: onSelected,
            child: child,
          );
        }

        if (!showPill) return shell;

        return Stack(
          children: [
            shell,
            Positioned(
              right: Spacing.s16,
              top: isDesktop ? Spacing.s16 : null,
              bottom: isDesktop ? null : kBottomNavigationBarHeight + Spacing.s16,
              child: AiFloatingPill(
                onTap: () => showAiChatSheet(context),
                onLongPress: () => context.go('/ai'),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _NavDestination {
  const _NavDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

List<_NavDestination> _navDestinations(AppLocalizations l10n) {
  return <_NavDestination>[
    _NavDestination(
      icon: Icons.dashboard_outlined,
      selectedIcon: Icons.dashboard,
      label: l10n.navHome,
    ),
    _NavDestination(
      icon: Icons.account_balance_wallet_outlined,
      selectedIcon: Icons.account_balance_wallet,
      label: l10n.navAssets,
    ),
    _NavDestination(
      icon: Icons.receipt_long_outlined,
      selectedIcon: Icons.receipt_long,
      label: l10n.navExpenses,
    ),
    _NavDestination(
      icon: Icons.pie_chart_outline,
      selectedIcon: Icons.pie_chart,
      label: l10n.navAnalytics,
    ),
    _NavDestination(
      icon: Icons.flag_outlined,
      selectedIcon: Icons.flag,
      label: l10n.navFire,
    ),
    _NavDestination(
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings,
      label: l10n.navSettings,
    ),
  ];
}

class _MobileShell extends StatelessWidget {
  const _MobileShell({
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.child,
  });

  final List<_NavDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // `extendBody: true` lets the body paint underneath the bottom nav,
    // which is what the glass blur composes over — without it, the bar
    // sits on a solid scaffold gap and the blur has nothing to read.
    return Scaffold(
      extendBody: true,
      body: child,
      bottomNavigationBar: GlassNavigationBar(
        selectedIndex: selectedIndex,
        destinations: [
          for (final d in destinations)
            NavigationDestination(
              icon: Icon(d.icon),
              selectedIcon: Icon(d.selectedIcon),
              label: d.label,
            ),
        ],
        onDestinationSelected: onDestinationSelected,
      ),
    );
  }
}

class _TabletShell extends StatelessWidget {
  const _TabletShell({
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.extended,
    required this.child,
  });

  final List<_NavDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final bool extended;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            NavigationRail(
              selectedIndex: selectedIndex,
              onDestinationSelected: onDestinationSelected,
              extended: extended,
              labelType: extended
                  ? NavigationRailLabelType.none
                  : NavigationRailLabelType.all,
              destinations: [
                for (final d in destinations)
                  NavigationRailDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.selectedIcon),
                    label: Text(d.label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1, thickness: 1),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

class _DesktopShell extends ConsumerWidget {
  const _DesktopShell({
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.child,
  });

  final List<_NavDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collapsed = ref.watch(sidebarCollapsedProvider);
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            DesktopSidebar(
              destinations: [
                for (final d in destinations)
                  DesktopSidebarDestination(
                    icon: d.icon,
                    selectedIcon: d.selectedIcon,
                    label: d.label,
                  ),
              ],
              selectedIndex: selectedIndex,
              onDestinationSelected: onDestinationSelected,
            ),
            Expanded(
              child: collapsed
                  ? Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: kCollapsedContentMaxWidth,
                        ),
                        child: child,
                      ),
                    )
                  : child,
            ),
          ],
        ),
      ),
    );
  }
}
