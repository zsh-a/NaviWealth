import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../core/ai/write/persistent_undo_banner.dart';
import '../core/shortcuts/shortcut_intents.dart';
import '../design_system/design_system.dart';
import '../features/ai_chat/state/route_context_provider.dart';
import '../features/ingest/data/share_intent_service.dart';
import '../l10n/gen/app_localizations.dart';
import 'desktop_sidebar.dart';

/// Root shell that hosts the 4-tab IndexedStack:
///   Home / Activity / Accounts / Settings.
///
/// Layout adapts at the breakpoints documented in
/// `docs/design/01-responsive-layout.md`:
///  - mobile (<600dp): bottom navigation bar.
///  - tablet (600-1240dp): slim icon rail on the left.
///  - desktop (>=1240dp): full sidebar via [DesktopSidebar].
///
/// AI is no longer a destination tab (§5.10): the command palette overlay
/// (Layer 1) and inline capsules (Layer 2) carry the explicit surfaces;
/// chat session history lives under `/settings/ai-history`.
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
    // §5.10.10 / S5c-native — app-wide share receiver. Self-guarded:
    // a no-op wherever the share channel is absent (tests / web /
    // desktop), so this is safe to start unconditionally here.
    ref.read(shareIntentServiceProvider).start();
  }

  @override
  void dispose() {
    ref.read(shareIntentServiceProvider).stop();
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
      icon: Icons.receipt_long_outlined,
      selectedIcon: Icons.receipt_long,
      label: l10n.navActivity,
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
    const commandIndex = 2;
    final navIndex = selectedIndex < commandIndex
        ? selectedIndex
        : selectedIndex + 1;

    void onNavChange(int i) {
      if (i == commandIndex) {
        Actions.maybeInvoke(context, const OpenCommandPaletteIntent());
        return;
      }
      onDestinationSelected(i < commandIndex ? i : i - 1);
    }

    FBottomNavigationBarItem itemFor(int i) {
      return FBottomNavigationBarItem(
        icon: Icon(
          i == selectedIndex
              ? destinations[i].selectedIcon
              : destinations[i].icon,
        ),
        label: Text(destinations[i].label),
      );
    }

    final l10n = AppLocalizations.of(context);

    return FScaffold(
      childPad: false,
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Wave 35 — persistent undo banner sits between content and
          // the bottom nav. Hidden when the stack is empty.
          const PersistentUndoBanner(),
          FBottomNavigationBar(
            index: navIndex,
            onChange: onNavChange,
            safeAreaBottom: true,
            children: [
              itemFor(0),
              itemFor(1),
              FBottomNavigationBarItem(
                icon: const Icon(Icons.search),
                label: Text(l10n.navSearch),
              ),
              itemFor(2),
              itemFor(3),
            ],
          ),
        ],
      ),
      child: child,
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
    final iconColor = selected ? colors.primary : colors.mutedForeground;
    final fill = selected ? colors.muted : Colors.transparent;
    return FTappable(
      onPress: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: fill,
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
      child: child,
    );
  }
}
