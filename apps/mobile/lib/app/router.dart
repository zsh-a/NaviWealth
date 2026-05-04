import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as lgw;

import '../design_system/design_system.dart';

// Tabs other than home are split into their own dart2js part files; each part
// is loaded the first time the user navigates to that route. Home ships in
// main.dart.js to avoid a part-file fetch on first paint. See
// docs/web-bundle.md for the resulting bundle layout.
import '../features/accounts/account_form_page.dart';
import '../features/accounts/accounts_page.dart';
import '../features/accounts/journal_entry_list_page.dart';
import '../features/accounts/transfer_form_page.dart';
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
import '../features/me/me_page.dart';
import '../features/portfolio/portfolio_page.dart' deferred as portfolio_lib;
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

/// Paths of the four primary tabs in the root shell, in display order.
///
/// The keyboard-shortcut layer (`core/shortcuts`) maps digits `1`-`4` to these
/// indexes — keep order in sync with `_RootShell`'s NavigationBar.
const List<String> kPrimaryTabPaths = <String>[
  '/',
  '/portfolio',
  '/analytics',
  '/me',
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
          // ── Portfolio tab (assets + liabilities) ──────────────────────
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
                    builder: (context, state) => const JournalEntryListPage(),
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
          // ── Legacy /assets redirect → /portfolio ─────────────────────
          GoRoute(
            path: '/assets',
            redirect: (context, state) {
              final uri = state.uri.toString();
              return uri.replaceFirst('/assets', '/portfolio');
            },
            routes: [
              GoRoute(
                path: ':_(.*)',
                redirect: (context, state) {
                  final uri = state.uri.toString();
                  return uri.replaceFirst('/assets', '/portfolio');
                },
              ),
            ],
          ),
          // ── Legacy /accounts redirect → /portfolio/accounts ───────────
          GoRoute(
            path: '/accounts',
            redirect: (context, state) {
              final uri = state.uri.toString();
              return uri.replaceFirst('/accounts', '/portfolio/accounts');
            },
            routes: [
              GoRoute(
                path: ':_(.*)',
                redirect: (context, state) {
                  final uri = state.uri.toString();
                  return uri.replaceFirst('/accounts', '/portfolio/accounts');
                },
              ),
            ],
          ),
          // ── Legacy /expenses redirect → /portfolio/expenses ───────────
          GoRoute(
            path: '/expenses',
            redirect: (context, state) {
              final uri = state.uri.toString();
              return uri.replaceFirst('/expenses', '/portfolio/expenses');
            },
            routes: [
              GoRoute(
                path: ':_(.*)',
                redirect: (context, state) {
                  final uri = state.uri.toString();
                  return uri.replaceFirst('/expenses', '/portfolio/expenses');
                },
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
            routes: [
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
          // ── Legacy /fire redirect → /analytics/fire ─────────────────
          GoRoute(
            path: '/fire',
            redirect: (context, state) => '/analytics/fire',
          ),
          // ── Legacy /rebalance redirect → /analytics/rebalance ───────
          GoRoute(
            path: '/rebalance',
            redirect: (context, state) => '/analytics/rebalance',
          ),
          GoRoute(
            path: '/ai',
            name: 'ai-chat',
            builder: (context, state) => DeferredRoute(
              load: ai_chat_lib.loadLibrary,
              builder: (_) => ai_chat_lib.AiChatPage(),
            ),
          ),
          // ── Me tab (hub: accounts, expenses, AI, settings) ─────────
          GoRoute(
            path: '/me',
            name: 'me',
            builder: (context, state) => const MePage(),
            routes: [
              GoRoute(
                path: 'ai',
                name: 'me-ai',
                builder: (context, state) => DeferredRoute(
                  load: ai_chat_lib.loadLibrary,
                  builder: (_) => ai_chat_lib.AiChatPage(),
                ),
              ),
              GoRoute(
                path: 'accounts',
                redirect: (context, state) {
                  final rest = state.uri.toString().replaceFirst(
                        '/me/accounts',
                        '/portfolio/accounts',
                      );
                  return rest;
                },
                routes: [
                  GoRoute(
                    path: ':_(.*)',
                    redirect: (context, state) {
                      final rest = state.uri.toString().replaceFirst(
                            '/me/accounts',
                            '/portfolio/accounts',
                          );
                      return rest;
                    },
                  ),
                ],
              ),
              GoRoute(
                path: 'expenses',
                redirect: (context, state) {
                  final rest = state.uri.toString().replaceFirst(
                        '/me/expenses',
                        '/portfolio/expenses',
                      );
                  return rest;
                },
                routes: [
                  GoRoute(
                    path: ':_(.*)',
                    redirect: (context, state) {
                      final rest = state.uri.toString().replaceFirst(
                            '/me/expenses',
                            '/portfolio/expenses',
                          );
                      return rest;
                    },
                  ),
                ],
              ),
              GoRoute(
                path: 'settings',
                redirect: (context, state) {
                  final rest = state.uri.toString().replaceFirst(
                        '/me/settings',
                        '/settings',
                      );
                  return rest;
                },
                routes: [
                  GoRoute(
                    path: ':_(.*)',
                    redirect: (context, state) {
                      final rest = state.uri.toString().replaceFirst(
                            '/me/settings',
                            '/settings',
                          );
                      return rest;
                    },
                  ),
                ],
              ),
            ],
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
          // ── Legacy /more redirect → / ────────────────────────────────
          GoRoute(
            path: '/more',
            redirect: (context, state) => '/',
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
    // Tab index resolution for the 4-tab layout:
    // Home(0) | Portfolio(1) | Analytics(2) | Me(3)
    final int index;
    if (location.startsWith('/portfolio') ||
        location.startsWith('/assets') ||
        location.startsWith('/expenses') ||
        location.startsWith('/accounts')) {
      index = 1;
    } else if (location.startsWith('/analytics') ||
        location.startsWith('/fire') ||
        location.startsWith('/rebalance')) {
      index = 2;
    } else if (location.startsWith('/me') ||
        location.startsWith('/ai') ||
        location.startsWith('/settings')) {
      index = 3;
    } else {
      index = 0;
    }
    final destinations = _navDestinations(l10n);
    void onSelected(int i) {
      if (i < 0 || i >= kPrimaryTabPaths.length) return;
      context.go(kPrimaryTabPaths[i]);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final isDesktop = width >= _desktopBreakpoint;

        if (isDesktop) {
          return _DesktopShell(
            destinations: destinations,
            selectedIndex: index,
            onDestinationSelected: onSelected,
            child: child,
          );
        }
        if (width >= _tabletBreakpoint) {
          return _TabletShell(
            destinations: destinations,
            selectedIndex: index,
            onDestinationSelected: onSelected,
            extended: width >= _railExtendedBreakpoint,
            child: child,
          );
        }
        return _MobileShell(
          destinations: destinations,
          selectedIndex: index,
          onDestinationSelected: onSelected,
          child: child,
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
      icon: Icons.pie_chart_outline,
      selectedIcon: Icons.pie_chart,
      label: l10n.navAnalytics,
    ),
    _NavDestination(
      icon: Icons.person_outline,
      selectedIcon: Icons.person,
      label: l10n.navMe,
    ),
  ];
}

class _MobileShell extends StatefulWidget {
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
  State<_MobileShell> createState() => _MobileShellState();
}

class _MobileShellState extends State<_MobileShell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _dialController = AnimationController(
    duration: const Duration(milliseconds: 350),
    vsync: this,
  );

  @override
  void dispose() {
    _dialController.dispose();
    super.dispose();
  }

  void _toggleSpeedDial() {
    if (_dialController.isAnimating) return;
    if (_dialController.isCompleted) {
      _dialController.reverse();
    } else {
      _dialController.forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final glowColors = lgw.GlassThemeData.of(context).glowColorsFor(context);

    // Android 3-button nav: push bar above opaque buttons.
    // On iOS / gesture-nav Android, sysBottom is 0.
    final platform = Theme.of(context).platform;
    final isIOS =
        platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;
    final sysBottom = isIOS ? 0.0 : MediaQuery.viewPaddingOf(context).bottom;
    const gap = 4.0;

    return Stack(
      children: [
        Positioned.fill(child: widget.child),
        // Speed-dial scrim — always in tree so it can listen to animation.
        AnimatedBuilder(
          animation: _dialController,
          builder: (context, _) {
            if (_dialController.value == 0) return const SizedBox.shrink();
            final t = Curves.easeOut.transform(_dialController.value);
            return Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _dialController.reverse(),
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 16 * t, sigmaY: 16 * t),
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: 0.25 * t),
                  ),
                ),
              ),
            );
          },
        ),
        // Action list — always in tree, positioned above the bar.
        AnimatedBuilder(
          animation: _dialController,
          builder: (context, _) {
            if (_dialController.value == 0) return const SizedBox.shrink();
            return Positioned(
              left: 0,
              right: 0,
              bottom: sysBottom + _MobileShell.barHeight + gap,
              child: _SpeedDialActions(
                controller: _dialController,
                onDismiss: () => _dialController.reverse(),
              ),
            );
          },
        ),
        // Glass bottom bar — always at the screen bottom.
        Positioned(
          left: 0,
          right: 0,
          bottom: sysBottom,
          child: lgw.GlassBottomBar(
            barHeight: _MobileShell.barHeight,
            verticalPadding: 0,
            quality: lgw.GlassQuality.premium,
            selectedIndex: widget.selectedIndex,
            onTabSelected: widget.onDestinationSelected,
            tabs: [
              for (final d in widget.destinations)
                lgw.GlassBottomBarTab(
                  label: d.label,
                  icon: Icon(d.icon),
                  activeIcon: Icon(d.selectedIcon),
                  glowColor: glowColors.primary,
                ),
            ],
            extraButton: lgw.GlassBottomBarExtraButton(
              icon: const Icon(Icons.add, color: Colors.white, size: 24),
              label: l10n.superFabTrade,
              size: 56,
              onTap: _toggleSpeedDial,
            ),
          ),
        ),
      ],
    );
  }
}

class _SpeedDialAction {
  const _SpeedDialAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
}

/// Animated list of speed-dial action chips.
class _SpeedDialActions extends StatelessWidget {
  const _SpeedDialActions({
    required this.controller,
    required this.onDismiss,
  });

  final AnimationController controller;
  final VoidCallback onDismiss;

  static const double _actionHeight = 52.0;
  static const double _actionGap = 10.0;
  static const double _actionHorizontalPadding = 16.0;
  static const _staggerStep = 0.08;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final actions = <_SpeedDialAction>[
      _SpeedDialAction(
        icon: Icons.swap_horiz,
        label: l10n.superFabTrade,
        onTap: () => context.push('/portfolio/trade'),
      ),
      _SpeedDialAction(
        icon: Icons.receipt_long_outlined,
        label: l10n.superFabExpense,
        onTap: () => context.push('/portfolio/expenses/new'),
      ),
      _SpeedDialAction(
        icon: Icons.swap_vert,
        label: l10n.superFabTransfer,
        onTap: () => context.push('/portfolio/accounts/transfer'),
      ),
      _SpeedDialAction(
        icon: Icons.account_balance_wallet_outlined,
        label: l10n.superFabAsset,
        onTap: () => context.push('/portfolio/new/cash'),
      ),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < actions.length; i++)
          _buildItem(actions[i], i, actions.length),
      ],
    );
  }

  Widget _buildItem(_SpeedDialAction action, int index, int total) {
    final reversedIndex = total - 1 - index;
    final stagger = reversedIndex * _staggerStep;
    final itemT = (controller.value - stagger).clamp(0.0, 1.0);
    final curved = Curves.easeOutCubic.transform(itemT);
    final slideOffset = (1 - curved) * 24.0;

    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        return Opacity(
          opacity: itemT.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, slideOffset),
            child: child,
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.only(bottom: _actionGap),
        child: _GlassActionChip(
          action: action,
          height: _actionHeight,
          horizontalPadding: _actionHorizontalPadding,
          onDismiss: onDismiss,
        ),
      ),
    );
  }
}

/// Glass-style action chip for the speed-dial overlay.
class _GlassActionChip extends StatelessWidget {
  const _GlassActionChip({
    required this.action,
    required this.height,
    required this.horizontalPadding,
    required this.onDismiss,
  });

  final _SpeedDialAction action;
  final double height;
  final double horizontalPadding;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        onDismiss();
        action.onTap();
      },
      child: lgw.GlassContainer(
        useOwnLayer: true,
        quality: lgw.GlassQuality.minimal,
        height: height,
        margin: const EdgeInsets.symmetric(horizontal: Spacing.s24),
        padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
        shape: const lgw.LiquidRoundedSuperellipse(borderRadius: Radii.full),
        clipBehavior: Clip.antiAlias,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: ColorPalette.brand500.withValues(alpha: 0.15),
              ),
              alignment: Alignment.center,
              child: Icon(action.icon, size: 18, color: ColorPalette.brand500),
            ),
            const SizedBox(width: Spacing.s12),
            Flexible(
              child: Text(
                action.label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : theme.colorScheme.onSurface,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
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
