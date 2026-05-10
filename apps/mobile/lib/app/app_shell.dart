import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as lgw;

import '../design_system/design_system.dart';
import '../features/ai_chat/state/route_context_provider.dart';
import '../l10n/gen/app_localizations.dart';
import 'desktop_sidebar.dart';
import 'global_action_panel.dart';

class AppRootShell extends ConsumerStatefulWidget {
  const AppRootShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  // Breakpoints mirror docs/design/01-responsive-layout.md. 1240 keeps a
  // >=720dp content column next to a ~256dp permanent drawer.
  static const double _tabletBreakpoint = 600;
  static const double _desktopBreakpoint = 1240;

  @override
  ConsumerState<AppRootShell> createState() => _AppRootShellState();
}

class _AppRootShellState extends ConsumerState<AppRootShell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: Motion.medium);
    _fade = CurvedAnimation(
      parent: _controller,
      curve: Motion.emphasizedDecelerate,
    );
    // Start fully opaque; the fade only triggers on subsequent tab switches.
    _controller.value = 1.0;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(AppRootShell old) {
    super.didUpdateWidget(old);
    if (widget.shell.currentIndex != old.shell.currentIndex) {
      _controller.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final shell = widget.shell;

    final location = GoRouter.of(
      context,
    ).routeInformationProvider.value.uri.path;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final current = ref.read(aiRouteContextProvider);
      if (current.path != location) {
        ref.read(aiRouteContextProvider.notifier).state = AiRouteContext(
          path: location,
        );
      }
    });

    final destinations = _navDestinations(l10n);
    final index = shell.currentIndex;
    void onSelected(int i) {
      shell.goBranch(i, initialLocation: i == shell.currentIndex);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final animatedChild = FadeTransition(opacity: _fade, child: shell);

        if (width >= AppRootShell._desktopBreakpoint) {
          return _DesktopShell(
            destinations: destinations,
            selectedIndex: index,
            onDestinationSelected: onSelected,
            child: animatedChild,
          );
        }
        if (width >= AppRootShell._tabletBreakpoint) {
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

    final platform = Theme.of(context).platform;
    final isIOS =
        platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;
    final sysBottom = isIOS ? 0.0 : MediaQuery.viewPaddingOf(context).bottom;

    // Per-shell `GlassBackdropScope` forces a fresh backdrop capture when
    // the shell first mounts. Without it, premium glass surfaces inside
    // the shell (notably `GlassBottomBar` below) can sample a stale or
    // uninitialised root backdrop on the very first frame — visible on
    // Android as a black screen that only clears once a scroll triggers
    // invalidation. See liquid_glass_widgets README §"Backdrop Isolation".
    return lgw.GlassBackdropScope(
      child: Stack(
      children: [
        Positioned.fill(
          child: Padding(
            padding: EdgeInsets.only(bottom: barHeight + sysBottom),
            child: child,
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: sysBottom,
          child: DefaultTextStyle(
            style: DefaultTextStyle.of(
              context,
            ).style.copyWith(decoration: TextDecoration.none),
            child: Builder(
              builder: (context) {
                final isScrolling = ScrollingScope.of(context);
                return lgw.GlassBottomBar(
                  barHeight: barHeight,
                  verticalPadding: 0,
                  labelFontSize: 10,
                  iconLabelSpacing: 0,
                  quality: isScrolling
                      ? lgw.GlassQuality.minimal
                      : lgw.GlassQuality.premium,
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
                );
              },
            ),
          ),
        ),
        Positioned(
          right: Spacing.s16,
          bottom: sysBottom + barHeight + Spacing.s16,
          child: Material(
            type: MaterialType.transparency,
            child: AppFab(
              tooltip: AppLocalizations.of(context).assetsAddAction,
              onPressed: () => showGlobalActionPanel(context),
              child: const Icon(Icons.add),
            ),
          ),
        ),
      ],
      ),
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
    // See `_MobileShell` for why this scope wraps the shell.
    return lgw.GlassBackdropScope(
      child: Scaffold(
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
              Expanded(child: _GlobalActionHost(child: child)),
            ],
          ),
        ),
      ),
    );
  }
}

class _DesktopShell extends StatelessWidget {
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
  Widget build(BuildContext context) {
    // Width capping is delegated to `PageScaffold`: single-pane pages
    // center their content at `Spacing.contentMaxWidth`, master-detail
    // pages (Accounts / Assets / AI Chat) intentionally fill the full
    // remaining width to give the splitter room to breathe.
    //
    // See `_MobileShell` for why this scope wraps the shell.
    return lgw.GlassBackdropScope(
      child: Scaffold(
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
              Expanded(child: _GlobalActionHost(child: child)),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlobalActionHost extends StatelessWidget {
  const _GlobalActionHost({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: child),
        Positioned(
          right: Spacing.s24,
          bottom: Spacing.s24,
          child: Material(
            type: MaterialType.transparency,
            child: AppFab(
              tooltip: AppLocalizations.of(context).assetsAddAction,
              onPressed: () => showGlobalActionPanel(context),
              child: const Icon(Icons.add),
            ),
          ),
        ),
      ],
    );
  }
}
