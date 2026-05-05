import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as lgw;

// Tabs other than home are split into their own dart2js part files; each part
// is loaded the first time the user navigates to that route. Home ships in
// main.dart.js to avoid a part-file fetch on first paint. See
// docs/web-bundle.md for the resulting bundle layout.
import '../core/logging/providers.dart';
import '../core/logging/talker_route_observer.dart';
import '../design_system/design_system.dart';
import '../features/accounts/account_form_page.dart';
import '../features/accounts/accounts_page.dart';
import '../features/accounts/journal_entry_list_page.dart';
import '../features/accounts/transfer_form_page.dart';
import '../features/activity/activity_page.dart';
import '../features/ai_chat/state/route_context_provider.dart';
import '../features/ai_chat/ui/ai_chat_page.dart' deferred as ai_chat_lib;
import '../features/analytics/analytics_page.dart' deferred as analytics_lib;
import '../features/assets/asset_detail_page.dart';
import '../features/assets/cash_form_page.dart';
import '../features/assets/deposit_form_page.dart';
import '../features/assets/physical/ui/physical_asset_detail_page.dart'
    deferred as physical_detail_lib;
import '../features/assets/wealth_product_form_page.dart';
import '../features/auth/presentation/devices_page.dart'
    deferred as devices_lib;
import '../features/auth/presentation/login_page.dart';
import '../features/expense/ui/expense_form_page.dart';
import '../features/expense/ui/expense_list_page.dart';
import '../features/expense/ui/expense_report_page.dart';
import '../features/fire/presentation/fire_page.dart' deferred as fire_lib;
import '../features/home/home_page.dart';
import '../features/investment/presentation/corporate_action_entry_route.dart'
    deferred as corp_action_lib;
import '../features/investment/presentation/trade_entry_form_page.dart';
import '../features/liabilities/ui/liabilities_page.dart'
    deferred as liabilities_lib;
import '../features/liabilities/ui/liability_detail_page.dart'
    deferred as liability_detail_lib;
import '../features/liabilities/ui/liability_form_page.dart';
import '../features/plan/plan_page.dart';
import '../features/portfolio/portfolio_page.dart' deferred as portfolio_lib;
import '../features/rebalance/ui/rebalance_page.dart' deferred as rebalance_lib;
import '../features/settings/backup/backup_page.dart';
import '../features/settings/fx_rates/fx_rates_page.dart';
import '../features/settings/log_viewer_page.dart';
import '../features/settings/settings_page.dart' deferred as settings_lib;
import '../l10n/gen/app_localizations.dart';
import 'deferred_route.dart';
import 'desktop_sidebar.dart';
import 'page_transitions.dart';
import 'route_analytics_observer.dart';
import 'route_error_page.dart';
import 'route_guard.dart';
import 'shell_preferences.dart';

/// Paths of the four primary tabs in the root shell, in display order.
///
/// The keyboard-shortcut layer (`core/shortcuts`) maps digits `1`-`4` to these
/// indexes — keep order in sync with `_RootShell`'s NavigationBar.
const List<String> kPrimaryTabPaths = <String>[
  '/',
  '/portfolio',
  '/activity',
  '/plan',
];

/// Test-only: eagerly resolve every deferred-as library the router maps to
/// a tab so subsequent [DeferredRoute] mounts see an already-completed
/// `loadLibrary()` future. Without this, widget tests sit on the loading
/// spinner — `loadLibrary()` is real-async and the fake test clock can't
/// drive it. Call from `setUpAll` inside a `runAsync` block.
@visibleForTesting
Future<void> preloadDeferredRoutesForTest() async {
  await Future.wait<void>(<Future<void>>[
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
    portfolio_lib.loadLibrary(),
  ]);
}

/// Builds the app's [GoRouter]. Exposed (rather than inlined in the provider)
/// so tests can construct a router seeded at an arbitrary deep-link location
/// and inject their own observers / guards through the [Ref].
GoRouter buildAppRouter(Ref ref, {String initialLocation = '/'}) {
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
        path: '/login',
        name: 'login',
        builder: (context, state) => const LoginPage(),
      ),
      // ── Main shell: IndexedStack preserves tab state across switches ──
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => _RootShell(shell: shell),
        branches: [
          // ── Branch 0: Home (+ AI Chat, Settings — no dedicated tab) ──
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/',
              name: 'home',
              builder: (context, state) => const HomePage(),
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
                GoRoute(
                  path: 'backup',
                  name: 'backup',
                  builder: (context, state) => const BackupPage(),
                ),
                GoRoute(
                  path: 'logs',
                  name: 'logs',
                  builder: (context, state) => const LogViewerPage(),
                ),
              ],
            ),
          ]),
          // ── Branch 1: Portfolio (assets + liabilities) ──────────────
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/portfolio',
              name: 'portfolio',
              builder: (context, state) => DeferredRoute(
                load: portfolio_lib.loadLibrary,
                builder: (_) => portfolio_lib.PortfolioPage(),
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
                    builder: (_) =>
                        corp_action_lib.CorporateActionEntryRoute(),
                  ),
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
                      path: 'new',
                      name: 'liability-new',
                      builder: (context, state) =>
                          const LiabilityFormPage(),
                    ),
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
                  pageBuilder: (context, state) =>
                      buildHeroAwareTransitionPage<void>(
                    context: context,
                    state: state,
                    child: AssetDetailPage(
                      assetId: state.pathParameters['assetId']!,
                    ),
                  ),
                ),
              ],
            ),
          ]),
          // ── Branch 2: Activity (expenses, accounts, trades) ─────────
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/activity',
              name: 'activity',
              builder: (context, state) => const ActivityPage(),
              routes: [
                GoRoute(
                  path: 'expenses',
                  name: 'expenses',
                  builder: (context, state) => const ExpenseListPage(),
                  routes: [
                    GoRoute(
                      path: 'new',
                      name: 'expense-new',
                      builder: (context, state) => const ExpenseFormPage(),
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
                  path: 'accounts',
                  name: 'accounts',
                  builder: (context, state) => const AccountsPage(),
                  routes: [
                    GoRoute(
                      path: 'new',
                      name: 'account-new',
                      builder: (context, state) => const AccountFormPage(),
                    ),
                    GoRoute(
                      path: 'transfer',
                      name: 'account-transfer',
                      builder: (context, state) => const TransferFormPage(),
                    ),
                    GoRoute(
                      path: 'journal',
                      name: 'account-journal',
                      builder: (context, state) =>
                          const JournalEntryListPage(),
                    ),
                    GoRoute(
                      path: ':accountId',
                      name: 'account-detail',
                      pageBuilder: (context, state) =>
                          buildHeroAwareTransitionPage<void>(
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
              ],
            ),
          ]),
          // ── Branch 3: Plan (analytics, FIRE, rebalance) ─────────────
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/plan',
              name: 'plan',
              builder: (context, state) => const PlanPage(),
              routes: [
                GoRoute(
                  path: 'analytics',
                  name: 'analytics',
                  builder: (context, state) => DeferredRoute(
                    load: analytics_lib.loadLibrary,
                    builder: (_) => analytics_lib.AnalyticsPage(),
                  ),
                ),
                GoRoute(
                  path: 'fire',
                  name: 'fire',
                  builder: (context, state) => DeferredRoute(
                    load: fire_lib.loadLibrary,
                    builder: (_) => fire_lib.FirePage(),
                  ),
                ),
                GoRoute(
                  path: 'rebalance',
                  name: 'rebalance',
                  builder: (context, state) => DeferredRoute(
                    load: rebalance_lib.loadLibrary,
                    builder: (_) => rebalance_lib.RebalancePage(),
                  ),
                ),
              ],
            ),
          ]),
        ],
      ),
      // ── Legacy redirects (top-level, no shell needed) ──────────────
      GoRoute(
        path: '/assets',
        redirect: (context, state) {
          final uri = state.uri.toString();
          if (uri == '/assets/trade') return '/activity/trade';
          return uri.replaceFirst('/assets', '/portfolio');
        },
        routes: [
          GoRoute(
            path: ':_(.*)',
            redirect: (context, state) {
              final uri = state.uri.toString();
              if (uri == '/assets/trade') return '/activity/trade';
              return uri.replaceFirst('/assets', '/portfolio');
            },
          ),
        ],
      ),
      GoRoute(
        path: '/accounts',
        redirect: (context, state) {
          final uri = state.uri.toString();
          return uri.replaceFirst('/accounts', '/activity/accounts');
        },
        routes: [
          GoRoute(
            path: ':_(.*)',
            redirect: (context, state) {
              final uri = state.uri.toString();
              return uri.replaceFirst('/accounts', '/activity/accounts');
            },
          ),
        ],
      ),
      GoRoute(
        path: '/expenses',
        redirect: (context, state) {
          final uri = state.uri.toString();
          return uri.replaceFirst('/expenses', '/activity/expenses');
        },
        routes: [
          GoRoute(
            path: ':_(.*)',
            redirect: (context, state) {
              final uri = state.uri.toString();
              return uri.replaceFirst('/expenses', '/activity/expenses');
            },
          ),
        ],
      ),
      GoRoute(
        path: '/analytics',
        redirect: (context, state) {
          final uri = state.uri.toString();
          return uri.replaceFirst('/analytics', '/plan/analytics');
        },
        routes: [
          GoRoute(
            path: ':_(.*)',
            redirect: (context, state) {
              final uri = state.uri.toString();
              return uri.replaceFirst('/analytics', '/plan/analytics');
            },
          ),
        ],
      ),
      GoRoute(
        path: '/fire',
        redirect: (context, state) => '/plan/fire',
      ),
      GoRoute(
        path: '/rebalance',
        redirect: (context, state) => '/plan/rebalance',
      ),
      GoRoute(
        path: '/me',
        redirect: (context, state) {
          final uri = state.uri.toString();
          if (uri == '/me') return '/';
          if (uri.startsWith('/me/accounts')) {
            return uri.replaceFirst('/me/accounts', '/activity/accounts');
          }
          if (uri.startsWith('/me/expenses')) {
            return uri.replaceFirst('/me/expenses', '/activity/expenses');
          }
          if (uri.startsWith('/me/ai')) return '/ai';
          if (uri.startsWith('/me/settings')) {
            return uri.replaceFirst('/me/settings', '/settings');
          }
          return '/';
        },
        routes: [
          GoRoute(
            path: ':_(.*)',
            redirect: (context, state) {
              final uri = state.uri.toString();
              if (uri.startsWith('/me/accounts')) {
                return uri.replaceFirst(
                    '/me/accounts', '/activity/accounts');
              }
              if (uri.startsWith('/me/expenses')) {
                return uri.replaceFirst(
                    '/me/expenses', '/activity/expenses');
              }
              if (uri.startsWith('/me/ai')) return '/ai';
              if (uri.startsWith('/me/settings')) {
                return uri.replaceFirst('/me/settings', '/settings');
              }
              return '/';
            },
          ),
        ],
      ),
      GoRoute(
        path: '/portfolio/accounts',
        redirect: (context, state) {
          final uri = state.uri.toString();
          return uri.replaceFirst(
              '/portfolio/accounts', '/activity/accounts');
        },
        routes: [
          GoRoute(
            path: ':_(.*)',
            redirect: (context, state) {
              final uri = state.uri.toString();
              return uri.replaceFirst(
                  '/portfolio/accounts', '/activity/accounts');
            },
          ),
        ],
      ),
      GoRoute(
        path: '/portfolio/expenses',
        redirect: (context, state) {
          final uri = state.uri.toString();
          return uri.replaceFirst(
              '/portfolio/expenses', '/activity/expenses');
        },
        routes: [
          GoRoute(
            path: ':_(.*)',
            redirect: (context, state) {
              final uri = state.uri.toString();
              return uri.replaceFirst(
                  '/portfolio/expenses', '/activity/expenses');
            },
          ),
        ],
      ),
      GoRoute(
        path: '/portfolio/trade',
        redirect: (context, state) => '/activity/trade',
      ),
      GoRoute(
        path: '/more',
        redirect: (context, state) => '/',
      ),
    ],
  );
}

final appRouterProvider = Provider<GoRouter>((ref) => buildAppRouter(ref));

class _RootShell extends ConsumerStatefulWidget {
  const _RootShell({required this.shell});

  final StatefulNavigationShell shell;

  // Breakpoints mirror docs/design/01-responsive-layout.md. 1240 keeps a
  // ≥720dp content column next to a ~256dp permanent drawer.
  static const double _tabletBreakpoint = 600;
  static const double _desktopBreakpoint = 1240;

  @override
  ConsumerState<_RootShell> createState() => _RootShellState();
}

class _RootShellState extends ConsumerState<_RootShell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Motion.medium,
    );
    _fade = CurvedAnimation(
      parent: _controller,
      curve: Motion.emphasizedDecelerate,
    );
    // Start fully opaque — the fade only triggers on subsequent tab switches.
    _controller.value = 1.0;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(_RootShell old) {
    super.didUpdateWidget(old);
    if (widget.shell.currentIndex != old.shell.currentIndex) {
      _controller.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final shell = widget.shell;

    // Keep the route context provider in sync with navigation.
    final location = GoRouter.of(
      context,
    ).routeInformationProvider.value.uri.path;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(aiRouteContextProvider.notifier).state = AiRouteContext(
        path: location,
      );
    });

    final destinations = _navDestinations(l10n);
    final index = shell.currentIndex;
    void onSelected(int i) {
      shell.goBranch(i, initialLocation: i == shell.currentIndex);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final isDesktop = width >= _RootShell._desktopBreakpoint;

        // Fade-in the new branch content on tab switch. The IndexedStack
        // inside the shell switches instantly; the fade softens the cut.
        final animatedChild = FadeTransition(
          opacity: _fade,
          child: shell,
        );

        if (isDesktop) {
          return _DesktopShell(
            destinations: destinations,
            selectedIndex: index,
            onDestinationSelected: onSelected,
            child: animatedChild,
          );
        }
        if (width >= _RootShell._tabletBreakpoint) {
          return _TabletShell(
            destinations: destinations,
            selectedIndex: index,
            onDestinationSelected: onSelected,
            child: animatedChild,
          );
        }
        return _MobileShell(
          destinations: destinations,
          selectedIndex: index,
          onDestinationSelected: onSelected,
          child: animatedChild,
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
      label: l10n.navPortfolio,
    ),
    _NavDestination(
      icon: Icons.receipt_long_outlined,
      selectedIcon: Icons.receipt_long,
      label: l10n.navActivity,
    ),
    _NavDestination(
      icon: Icons.flag_outlined,
      selectedIcon: Icons.flag,
      label: l10n.navPlan,
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

  static const double barHeight = 64;

  @override
  Widget build(BuildContext context) {
    final glowColors = lgw.GlassThemeData.of(context).glowColorsFor(context);

    // Android 3-button nav: push bar above opaque buttons.
    // On iOS / gesture-nav Android, sysBottom is 0.
    final platform = Theme.of(context).platform;
    final isIOS =
        platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;
    final sysBottom = isIOS ? 0.0 : MediaQuery.viewPaddingOf(context).bottom;

    return Stack(
      children: [
        Positioned.fill(
          child: Padding(
            padding: EdgeInsets.only(bottom: barHeight + sysBottom),
            child: child,
          ),
        ),
        // Glass bottom bar — always at the screen bottom.
        Positioned(
          left: 0,
          right: 0,
          bottom: sysBottom,
          child: DefaultTextStyle(
            style: DefaultTextStyle.of(context).style.copyWith(
                  decoration: TextDecoration.none,
                ),
            child: lgw.GlassBottomBar(
              barHeight: barHeight,
              verticalPadding: 0,
              labelFontSize: 10,
              iconLabelSpacing: 0,
              quality: lgw.GlassQuality.premium,
              selectedIndex: selectedIndex,
              onTabSelected: onDestinationSelected,
              tabs: [
                for (final d in destinations)
                  lgw.GlassBottomBarTab(
                    label: d.label,
                    icon: Icon(d.icon),
                    activeIcon: Icon(d.selectedIcon),
                    glowColor: glowColors.primary,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _TabletShell extends StatelessWidget {
  const _TabletShell({
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
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            lgw.GlassSideBar(
              width: 128,
              children: [
                for (var i = 0; i < destinations.length; i++)
                  lgw.GlassSideBarItem(
                    icon: Icon(
                      i == selectedIndex
                          ? destinations[i].selectedIcon
                          : destinations[i].icon,
                    ),
                    label: destinations[i].label,
                    isSelected: i == selectedIndex,
                    onTap: () => onDestinationSelected(i),
                  ),
              ],
            ),
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
