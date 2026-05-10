import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../design_system/design_system.dart';
import '../features/ai_chat/state/route_context_provider.dart';
import '../l10n/gen/app_localizations.dart';
import 'desktop_sidebar.dart';

/// Root shell that hosts the 5-tab IndexedStack:
///   Home / Activity / AI (centered accent) / Accounts / Settings.
///
/// Layout adapts at the breakpoints documented in
/// `docs/design/01-responsive-layout.md`:
///  - mobile (<600dp): bottom navigation bar with the AI tab visually
///    elevated as a teal accent disc.
///  - tablet (600-1240dp): slim icon rail on the left.
///  - desktop (>=1240dp): full sidebar via [DesktopSidebar].
///
/// The legacy "+ FAB" surface is gone — quick-add flows now live behind the
/// AI tab and the per-page header actions, keeping the calm finance
/// aesthetic uncluttered.
class AppRootShell extends ConsumerStatefulWidget {
  const AppRootShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

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
    this.isAccent = false,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;

  /// Center "AI" tab — rendered with the teal accent disc on mobile.
  final bool isAccent;
}

List<_NavDestination> _navDestinations(AppLocalizations l10n) {
  return <_NavDestination>[
    _NavDestination(
      icon: Icons.dashboard_outlined,
      selectedIcon: Icons.dashboard,
      label: l10n.navHome,
    ),
    _NavDestination(
      icon: Icons.receipt_long_outlined,
      selectedIcon: Icons.receipt_long,
      label: l10n.navActivity,
    ),
    _NavDestination(
      icon: Icons.auto_awesome_outlined,
      selectedIcon: Icons.auto_awesome,
      label: l10n.navAI,
      isAccent: true,
    ),
    _NavDestination(
      icon: Icons.account_balance_wallet_outlined,
      selectedIcon: Icons.account_balance_wallet,
      label: l10n.navAccounts,
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
    final colors = context.theme.colors;
    return FScaffold(
      childPad: false,
      footer: FBottomNavigationBar(
        index: selectedIndex,
        onChange: onDestinationSelected,
        safeAreaBottom: true,
        children: [
          for (var i = 0; i < destinations.length; i++)
            FBottomNavigationBarItem(
              icon: _MobileNavIcon(
                destination: destinations[i],
                selected: i == selectedIndex,
                accentColor: colors.primary,
              ),
              label: Text(destinations[i].label),
            ),
        ],
      ),
      child: child,
    );
  }
}

/// Mobile bottom-nav icon. Renders the AI center tab as an accent-tinted
/// disc so it pops above the surrounding gray-scale glyphs without
/// resorting to a separate floating FAB (which would clutter the calm
/// surface). Inactive non-accent tabs use the muted foreground; the
/// active non-accent tab uses the standard accent foreground.
class _MobileNavIcon extends StatelessWidget {
  const _MobileNavIcon({
    required this.destination,
    required this.selected,
    required this.accentColor,
  });

  final _NavDestination destination;
  final bool selected;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    if (destination.isAccent) {
      return Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: accentColor.withValues(alpha: selected ? 1.0 : 0.14),
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: Icon(
          selected ? destination.selectedIcon : destination.icon,
          size: 20,
          color: selected
              ? context.theme.colors.primaryForeground
              : accentColor,
        ),
      );
    }
    return Icon(selected ? destination.selectedIcon : destination.icon);
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
      child: child,
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
    final isAiTab = destination.isAccent;
    final iconColor = isAiTab
        ? (selected ? colors.primaryForeground : colors.primary)
        : (selected ? colors.primary : colors.mutedForeground);
    return FTappable(
      onPress: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isAiTab
              ? colors.primary.withValues(alpha: selected ? 1.0 : 0.12)
              : (selected ? colors.muted : Colors.transparent),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              selected ? destination.selectedIcon : destination.icon,
              color: iconColor,
              size: 22,
            ),
            const SizedBox(height: 4),
            Text(
              destination.label,
              style: context.theme.typography.xs.copyWith(
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: isAiTab && selected
                    ? colors.primaryForeground
                    : (selected ? colors.primary : colors.foreground),
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
              isAccent: d.isAccent,
            ),
        ],
        selectedIndex: selectedIndex,
        onDestinationSelected: onDestinationSelected,
      ),
      child: child,
    );
  }
}
