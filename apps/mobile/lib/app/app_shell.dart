import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

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

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    return Stack(
      children: [
        FScaffold(
          childPad: false,
          footer: FBottomNavigationBar(
            index: selectedIndex,
            onChange: onDestinationSelected,
            safeAreaBottom: true,
            children: [
              for (var i = 0; i < destinations.length; i++)
                FBottomNavigationBarItem(
                  icon: Icon(
                    i == selectedIndex
                        ? destinations[i].selectedIcon
                        : destinations[i].icon,
                  ),
                  label: Text(destinations[i].label),
                ),
            ],
          ),
          child: child,
        ),
        Positioned(
          right: 16,
          bottom: bottomInset + 80,
          child: SizedBox(
            width: 56,
            height: 56,
            child: FButton.icon(
              onPress: () => showGlobalActionPanel(context),
              child: const Icon(Icons.add, size: 24),
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
    return FScaffold(
      childPad: false,
      sidebar: SizedBox(
        width: 80,
        child: FSidebar(
          children: [
            for (var i = 0; i < destinations.length; i++)
              _TabletRailItem(
                destination: destinations[i],
                selected: i == selectedIndex,
                onTap: () => onDestinationSelected(i),
              ),
          ],
        ),
      ),
      child: _GlobalActionHost(child: child),
    );
  }
}

class _TabletRailItem extends StatelessWidget {
  const _TabletRailItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final _NavDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return FTappable(
      onPress: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? colors.muted : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              selected ? destination.selectedIcon : destination.icon,
              color: selected ? colors.primary : colors.mutedForeground,
              size: 22,
            ),
            const SizedBox(height: 4),
            Text(
              destination.label,
              style: context.theme.typography.xs.copyWith(
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected ? colors.primary : colors.foreground,
              ),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
          ],
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
    return FScaffold(
      childPad: false,
      sidebar: DesktopSidebar(
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
      child: _GlobalActionHost(child: child),
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
          right: 24,
          bottom: 24,
          child: SizedBox(
            width: 56,
            height: 56,
            child: FButton.icon(
              onPress: () => showGlobalActionPanel(context),
              child: const Icon(Icons.add, size: 24),
            ),
          ),
        ),
      ],
    );
  }
}
